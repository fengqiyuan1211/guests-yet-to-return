extends Node
## One owned-stock service for the shop, workbench and recipe display.
## A persisted intent plus an idempotent wallet receipt recovers a purchase once.
signal changed
signal shop_changed
signal purchase_completed(item_id: String, packages: int, total: int)

const InventoryScript := preload("res://scripts/supply_inventory.gd")
const PRICE_PATH := "res://data/supplies/shop_prices.json"
const SHOP_CATEGORIES := {"base_spirit": "原酒", "mixer": "配料", "garnish": "装饰品"}
var save_path := "user://supplies_state.json"
var price_path := PRICE_PATH
var last_error := ""
var writable := true
var wallet: Node
var menu: Node
var inventory: RefCounted = InventoryScript.new()
var catalog: RefCounted = inventory.catalog
var _prices: Dictionary = {}
var _pending: Dictionary = {}
var _pending_before: Dictionary = {}
var _busy := false
# Inventory and workbench contents share one atomic file.
var workbench: Dictionary = {}
var workbench_initialized := false

func _ready() -> void:
	for prefix in ["--slot-wallet=", "--dialogue-save=", "--game-save=", "--menu-save="]:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with(prefix):
				save_path = arg.trim_prefix(prefix) + ".supplies"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--supplies-save="):
			save_path = arg.trim_prefix("--supplies-save=")
	initialize(get_node_or_null("/root/SlotWallet"), get_node_or_null("/root/MenuCatalog"))

func initialize(wallet_service: Node, menu_service: Node) -> bool:
	wallet = wallet_service
	menu = menu_service
	if wallet != null and not wallet.balance_changed.is_connected(_on_balance_changed):
		wallet.balance_changed.connect(_on_balance_changed)
	if not load_prices() or not load_state():
		return false
	_sync_menu()
	return true

func _on_balance_changed(_balance: int) -> void:
	shop_changed.emit()

func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(value) and value >= minimum and value <= maximum

func load_prices() -> bool:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(price_path))
	if not data is Dictionary or data.get("schema_version") != 1 or data.get("price_basis") != "game_provisional" or not data.get("prices") is Dictionary:
		return _protect("商店价目暂时无法读取，请保留现有记录。")
	var next: Dictionary = {}
	for item: Dictionary in catalog.list_items():
		if item.storage_mode == "permanent":
			continue
		var price: Variant = data.prices.get(item.id)
		if not _whole(price, 1, 1000000):
			return _protect("商店里有尚未定价的商品。")
		next[item.id] = int(price)
	_prices = next
	return true

func list_shop_items(category := "") -> Array:
	var selected: String = SHOP_CATEGORIES.get(category, category)
	var result: Array = []
	for item: Dictionary in catalog.list_items(selected):
		if item.storage_mode == "permanent" or not item.get("shop_enabled",true):
			continue
		item.shop_price = get_unit_price(item.id)
		item.price_basis = "game_provisional"
		for key in SHOP_CATEGORIES:
			if SHOP_CATEGORIES[key] == item.category:
				item.shop_category = key
		result.append(item)
	return result

func get_item(id: String) -> Dictionary:
	return catalog.get_item(id)

func get_state(id: String) -> Dictionary:
	return inventory.get_state(id)

func is_owned(id: String) -> bool:
	return bool(get_state(id).get("owned", false))

func is_unlocked(id: String) -> bool:
	return inventory.is_unlocked(id)

func total_remaining(id: String) -> float:
	return inventory.total_remaining(id)

func as_recipe_inventory() -> Dictionary:
	return inventory.as_recipe_inventory()

func get_unit_price(id: String) -> int:
	return int(_prices.get(id, -1))

func missing_recipe_requirements(recipe_id: String) -> Dictionary:
	if menu == null:
		return {"ready": false, "ingredients": [], "equipment": [], "message": "酒谱暂时无法读取。"}
	var recipe: Dictionary = menu.get_recipe(recipe_id)
	if recipe.is_empty():
		return {"ready": false, "ingredients": [], "equipment": [], "message": "还没有这款酒的酒谱。"}
	return _recipe_requirements(recipe)

func _recipe_requirements(recipe: Dictionary) -> Dictionary:
	var missing_ingredients: Array = []
	var required_count := 0
	for ingredient: Dictionary in recipe.get("ingredients", []):
		if not ingredient.get("required", true) or menu._is_ice(ingredient):
			continue
		required_count += 1
		var id: String = str(ingredient.get("sku_id", ""))
		if not inventory.is_unlocked(id):
			missing_ingredients.append({"item_id": id, "name": ingredient.get("name", id)})
	# Required tools and glasses are available by default; only material discovery gates the codex.
	return {"ready": required_count > 0 and missing_ingredients.is_empty(),
		"ingredients": missing_ingredients, "equipment": [], "message": ""}

func quote_purchase(id: String, packages: Variant = 1) -> Dictionary:
	var item: Dictionary = catalog.get_item(id)
	var message := ""
	var price := get_unit_price(id)
	var total := 0
	if item.is_empty():
		message = "这个商品暂时不能购买。"
	elif item.storage_mode == "permanent":
		message = "酒馆已经备好这些器材和酒杯。"
	elif price < 1:
		message = "这个商品暂时不能购买。"
	elif not _whole(packages, 1, 1000):
		message = "每次请购买 1 到 1000 份。"
	elif not writable or _busy or not _pending.is_empty():
		message = last_error if not last_error.is_empty() else "请先完成上一笔购买。"
	elif wallet == null or not wallet.writable:
		message = "金币记录暂时无法读取。"
	elif menu != null and not menu.writable:
		message = "酒谱记录暂时无法读取，请保留原记录。"
	elif not wallet.pending.is_empty():
		message = "请先等待本轮老虎机结算。"
	else:
		total = price * int(packages)
		if wallet.balance < total:
			message = "金币不足，还需要 %d 金币。" % (total - wallet.balance)
	return {"ok": message.is_empty(), "unit_price": price, "total": total, "message": message}

func purchase(id: String, packages: Variant = 1) -> bool:
	var quote := quote_purchase(id, packages)
	if not quote.ok:
		last_error = quote.message
		return false
	_busy = true
	var before: Dictionary = inventory.serialize()
	var candidate: RefCounted = InventoryScript.new()
	if not candidate.restore(before) or not candidate.purchase(id, int(packages)):
		last_error = candidate.last_error
		_busy = false
		return false
	var transaction := {"id": "shop-%d-%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec(), randi()],
		"item_id": id, "packages": int(packages), "cost": int(quote.total), "inventory_after": candidate.serialize()}
	# The old stock is retained until the wallet durably acknowledges the debit.
	if not _write(before, transaction):
		_busy = false
		return false
	_pending = transaction
	_pending_before = before
	if not wallet.spend_for_purchase(transaction.id, transaction.cost):
		var failure: String = wallet.last_error
		if _write(before, {}):
			_pending = {}
			_pending_before = {}
		else:
			writable = false
		last_error = failure
		_busy = false
		return false
	inventory.restore(transaction.inventory_after)
	# Receipt + intent already guarantee this delivery even if the final write fails.
	if _write(inventory.serialize(), {}):
		_pending = {}
		_pending_before = {}
		wallet.forget_purchase_receipt(transaction.id)
		last_error = ""
	else:
		writable = false
		last_error = "已购入，购买记录将于下次打开时恢复。"
	_busy = false
	var settlement_message := last_error
	_sync_menu()
	if not settlement_message.is_empty():
		last_error = settlement_message
	changed.emit()
	shop_changed.emit()
	purchase_completed.emit(id, int(packages), int(quote.total))
	return true

func consume(id: String, amount: float) -> bool:
	return consume_many({id: amount})

func consume_many(amounts: Dictionary) -> bool:
	# Validate a complete pour before writing any of its ingredients.
	if not writable or _busy or not _pending.is_empty() or amounts.is_empty():
		last_error = "原料记录暂时无法保存。"
		return false
	var candidate: RefCounted = InventoryScript.new()
	if not candidate.restore(inventory.serialize()):
		return false
	for id in amounts:
		if not id is String or not (amounts[id] is int or amounts[id] is float) or not candidate.consume(id, float(amounts[id])):
			last_error = candidate.last_error if not candidate.last_error.is_empty() else "消耗内容或数量无效。"
			return false
	if not _write(candidate.serialize(), {}):
		return false
	inventory.restore(candidate.serialize())
	_sync_menu()
	changed.emit()
	shop_changed.emit()
	return true

func commit_workbench(next: Dictionary, amounts: Dictionary = {}) -> bool:
	# Publish neither side until the one shared snapshot has been renamed successfully.
	if not writable or _busy or not _pending.is_empty():
		last_error="库存记录尚未就绪，请稍后重试。"
		return false
	var candidate: RefCounted=InventoryScript.new()
	if not candidate.restore(inventory.serialize()): return false
	for id in amounts:
		if not id is String or not (amounts[id] is int or amounts[id] is float) or not candidate.consume(id,float(amounts[id])):
			last_error=candidate.last_error if not candidate.last_error.is_empty() else "消耗内容无效。"
			return false
	_busy=true
	var previous:=workbench
	workbench=next.duplicate(true)
	if not _write(candidate.serialize(),{}):
		workbench=previous
		_busy=false
		return false
	inventory.restore(candidate.serialize())
	workbench_initialized=true
	if not amounts.is_empty() or previous.get("research", {}).get("mastered", {}) != workbench.get("research", {}).get("mastered", {}): _sync_menu()
	_busy=false
	changed.emit()
	shop_changed.emit()
	return true

func serialize() -> Dictionary:
	# An unresolved intent is always paired with its original stock, even after debit.
	var state: Dictionary = inventory.serialize() if _pending.is_empty() else _pending_before.duplicate(true)
	return {"version": 1, "inventory": state, "pending": _pending.duplicate(true), "workbench": workbench.duplicate(true)}

func _protect(message: String) -> bool:
	writable = false
	last_error = message
	return false

func _valid_pending(transaction: Variant, before: Dictionary) -> bool:
	if not transaction is Dictionary:
		return false
	if transaction.is_empty():
		return true
	if not transaction.get("id") is String or transaction.id.is_empty() or transaction.id.length() > 128 or not transaction.get("item_id") is String:
		return false
	if not _whole(transaction.get("packages"), 1, 1000) or not _whole(transaction.get("cost"), 1, 1000000000):
		return false
	var candidate: RefCounted = InventoryScript.new()
	if not candidate.restore(before):
		return false
	var item: Dictionary = catalog.get_item(transaction.item_id)
	if item.is_empty():
		return false
	if item.storage_mode == "permanent":
		# Finish a purchase already debited by the previous version without a second charge.
		# Restoring both snapshots normalizes the newly free tools; ingredient stock must match.
		if transaction.packages != 1:
			return false
	elif not candidate.purchase(transaction.item_id, int(transaction.packages)):
		return false
	var after: RefCounted = InventoryScript.new()
	return after.restore(transaction.get("inventory_after")) and after.serialize() == candidate.serialize()

func load_state() -> bool:
	workbench={}
	workbench_initialized=false
	writable = true
	last_error = ""
	_pending = {}
	_pending_before = {}
	if not FileAccess.file_exists(save_path):
		inventory.reset()
		_migrate_legacy_totals()
		return true
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	var candidate: RefCounted = InventoryScript.new()
	if not data is Dictionary or data.get("version") != 1 or not candidate.restore(data.get("inventory")):
		return _protect("上次的库存未能读取，原记录已保留。")
	if not _valid_pending(data.get("pending", {}), candidate.serialize()):
		return _protect("上次的购买记录不完整，原记录已保留。")
	if not data.get("workbench", {}) is Dictionary:
		return _protect("工作台记录不完整，原库存已保留。")
	workbench=data.get("workbench", {}).duplicate(true)
	workbench_initialized=data.has("workbench")
	inventory.restore(candidate.serialize())
	_pending = data.get("pending", {}).duplicate(true)
	_pending_before = candidate.serialize() if not _pending.is_empty() else {}
	if not _pending.is_empty():
		return recover_pending()
	# Persist this upgrade immediately rather than leaving old owned=false flags on disk.
	var needs_default_migration := false
	for item: Dictionary in catalog.list_items():
		if item.storage_mode != "permanent" or item.get("unlock_policy", "available_by_default") != "available_by_default":
			continue
		var prior: Variant = data.inventory.items.get(item.id)
		if not prior is Dictionary or prior.get("owned") != true or prior.get("unlocked") != true:
			needs_default_migration = true
	if needs_default_migration and not _write(candidate.serialize(), {}):
		return _protect("器材记录尚未更新，原库存已保留，请重试。")
	return true

func recover_pending() -> bool:
	if _pending.is_empty():
		return true
	if wallet == null or not wallet.writable:
		return _protect("金币记录未能读取，购买记录已保留。")
	var transaction := _pending.duplicate(true)
	if wallet.purchase_receipts.has(transaction.id) and not wallet.has_purchase_receipt(transaction.id, transaction.cost):
		return _protect("金币与购买记录不一致，原记录已保留。")
	var paid: bool = wallet.has_purchase_receipt(transaction.id, transaction.cost)
	var recovered_inventory: RefCounted = InventoryScript.new()
	var recovered_source: Dictionary = transaction.inventory_after if paid else _pending_before
	if not recovered_inventory.restore(recovered_source):
		return _protect("上次的购买库存无法恢复，原记录已保留。")
	var recovered: Dictionary = recovered_inventory.serialize()
	if not _write(recovered, {}):
		return _protect("上次的购买尚未恢复，请保留记录后重试。")
	inventory.restore(recovered)
	_pending = {}
	_pending_before = {}
	writable = true
	if paid:
		wallet.forget_purchase_receipt(transaction.id)
	last_error = ""
	_sync_menu()
	changed.emit()
	shop_changed.emit()
	return true

func save_state() -> bool:
	if not _pending.is_empty():
		return recover_pending()
	return writable and _write(inventory.serialize(), {})

func reset_game() -> bool:
	# GameSession has already backed up every file after explicit confirmation.
	var initial: RefCounted = InventoryScript.new()
	var previous_workbench:=workbench
	workbench={}
	if not _write(initial.serialize(), {}):
		workbench=previous_workbench
		return false
	workbench_initialized=true
	inventory.restore(initial.serialize())
	_pending = {}
	_pending_before = {}
	writable = true
	last_error = ""
	_sync_menu()
	changed.emit()
	shop_changed.emit()
	return true

func _write(state: Dictionary, transaction: Dictionary) -> bool:
	var temporary := save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "库存未能保存，请检查存储空间后重试。"
		return false
	file.store_string(JSON.stringify({"version": 1, "inventory": state, "pending": transaction, "workbench": workbench}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(save_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		last_error = "库存未能保存，请重试。"
		return false
	last_error = ""
	return true

func _migrate_legacy_totals() -> void:
	# Preserve old menu-stock progress on the first upgrade to packaged inventory.
	if menu == null or not menu.writable:
		return
	var snapshot: Dictionary = inventory.serialize()
	for id in menu.inventory:
		var item: Dictionary = catalog.get_item(id)
		var total: float = float(menu.inventory[id])
		if item.is_empty() or item.kind != "ingredient" or total <= 0:
			continue
		if item.storage_mode == "quantity":
			if total == floor(total):
				snapshot.items[id] = {"unlocked": true, "quantity": int(total)}
		else:
			var capacity: float = float(item.package.container_capacity)
			var quantity := ceili(total / capacity)
			snapshot.items[id] = {"unlocked": true, "quantity": quantity, "current_remaining": total - (quantity - 1) * capacity}
	inventory.restore(snapshot)

func _sync_menu() -> bool:
	if menu == null or menu._waiting_for_research:
		return true
	var unlocked: Array = []
	for recipe: Dictionary in menu.all_recipes():
		if not recipe.get("source_guest", "").is_empty(): continue
		if recipe.get("unlock_kind") == "legendary_mastery":
			if workbench.get("research", {}).get("mastered", {}).has(recipe.id): unlocked.append(recipe.id)
		elif _recipe_requirements(recipe).ready:
			unlocked.append(recipe.id)
	if not menu.update_supply_inventory(inventory.as_recipe_inventory(), unlocked):
		last_error = "已保存库存，酒谱更新暂未完成。"
		return false
	return true

func grant_activity_equipment(id: String, activity_id: String) -> bool:
	var item: Dictionary = catalog.get_item(id)
	if item.get("storage_mode") != "permanent" or item.get("unlock_policy") != "activity_reward" or item.get("reward_activity_id") != activity_id:
		last_error = "这件纪念品暂时无法领取。"
		return false
	if not writable or _busy or not _pending.is_empty():
		last_error = "纪念品暂未保存，请稍后重试。"
		return false
	if is_owned(id): return true
	var snapshot: Dictionary = inventory.serialize()
	snapshot.items[id] = {"unlocked": true, "owned": true}
	var candidate: RefCounted = InventoryScript.new()
	if not candidate.restore(snapshot):
		last_error = candidate.last_error
		return false
	if not _write(candidate.serialize(), {}): return false
	inventory.restore(candidate.serialize())
	changed.emit()
	shop_changed.emit()
	return true
