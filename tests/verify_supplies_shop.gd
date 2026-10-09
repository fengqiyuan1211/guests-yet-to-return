extends Node
## Focused transaction and restart checks; every file lives in a private /tmp folder.
const ServiceScript := preload("res://scripts/supplies.gd")
const WalletScript := preload("res://scripts/slot_wallet.gd")
const MenuScript := preload("res://scripts/menu_catalog.gd")
const InventoryScript := preload("res://scripts/supply_inventory.gd")
var failures: Array[String] = []
var checks := 0
var temp_dir := "/tmp/tavern-shop-contract-%d" % Time.get_ticks_usec()
var objects: Array[Node] = []

class InterruptibleSupplies extends ServiceScript:
	var writes_left := -1
	func _write(state: Dictionary, transaction: Dictionary) -> bool:
		if writes_left == 0:
			last_error = "模拟落盘中断。"
			return false
		if writes_left > 0:
			writes_left -= 1
		return super._write(state, transaction)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func write_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Fixture can be written")
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()

func wallet_for(name: String, balance := 5000) -> Node:
	var wallet := WalletScript.new()
	objects.append(wallet)
	wallet.save_path = temp_dir.path_join(name + "-wallet.json")
	if FileAccess.file_exists(wallet.save_path):
		wallet.load_wallet()
	else:
		wallet.balance = balance
		check(wallet.persist(), "Private wallet persists")
	return wallet

func menu_for(name: String) -> Node:
	var menu := MenuScript.new()
	objects.append(menu)
	menu.save_path = temp_dir.path_join(name + "-menu.json")
	check(menu.load_catalog() and menu.load_state(), "Private canonical menu loads")
	return menu

func service_for(name: String, wallet: Node, menu: Node) -> Node:
	var service := ServiceScript.new()
	objects.append(service)
	service.save_path = temp_dir.path_join(name + "-supplies.json")
	check(service.initialize(wallet, menu), "Private shop loads")
	return service

func _ready() -> void:
	for name in ["SlotWallet", "StoryDialogue", "GameSession", "MenuCatalog", "Supplies"]:
		var singleton := get_node_or_null("/root/" + name)
		if singleton != null and not str(singleton.save_path).begins_with("/tmp/") and not str(singleton.save_path).begins_with("/private/tmp/"):
			push_error("Run only with isolated save paths")
			get_tree().quit(2)
			return
	TimeManager.set_process(false)
	GameSession.set_process(false)
	call_deferred("run")

func run() -> void:
	check(DirAccess.make_dir_recursive_absolute(temp_dir) == OK, "Private fixture directory exists")
	verify_purchase_and_unlock()
	verify_recipe_unlock_rules()
	verify_rejected_transactions()
	verify_recovery_boundaries()
	verify_legacy_and_protection()
	verify_default_equipment_migration()
	verify_legacy_equipment_intent()
	verify_global_restart()
	for object in objects:
		object.free()
	for file_name in DirAccess.get_files_at(temp_dir):
		DirAccess.remove_absolute(temp_dir.path_join(file_name))
	DirAccess.remove_absolute(temp_dir)
	SaloonAudio.set_process(false)
	if is_instance_valid(SaloonAudio.fade):
		SaloonAudio.fade.kill()
	for player in SaloonAudio.players:
		player.stop()
		player.stream = null
	SaloonAudio._streams.clear()
	print("SUPPLIES SHOP: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size(), " (", checks, " checks)")
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func verify_purchase_and_unlock() -> void:
	var wallet := wallet_for("normal")
	var menu := menu_for("normal")
	var service := service_for("normal", wallet, menu)
	check(service.list_shop_items().size() == 22, "22 consumables exclude six tools and four glasses")
	var expected := {"原酒": 10, "配料": 8, "装饰品": 4, "器材": 0, "杯型": 0}
	for category in expected:
		check(service.list_shop_items(category).size() == expected[category], "Product grouping: " + category)
	check(service.list_shop_items("base_spirit").size() == 10, "English category alias works")
	for item: Dictionary in service.list_shop_items():
		check(item.shop_price > 0 and item.price_basis == "game_provisional", "Every product has an explicit provisional price: " + item.id)
	for item: Dictionary in service.catalog.list_items():
		if item.storage_mode == "permanent":
			check(service.is_owned(item.id) and service.is_unlocked(item.id) and service.get_unit_price(item.id) == -1, "Tools and glasses are initially owned and have no shop price")
	var old_balance: int = wallet.balance
	check(service.purchase("sku_gin_london_dry", 2), "Two bottles can be bought")
	check(wallet.balance == old_balance - 2 * service.get_unit_price("sku_gin_london_dry") and service.total_remaining("sku_gin_london_dry") == 1500, "Quote debits pack price and grants exact bottle volume")
	check(service.consume("sku_gin_london_dry", 650) and service.purchase("sku_gin_london_dry"), "Opened bottle can be consumed and replenished")
	check(service.get_state("sku_gin_london_dry").current_remaining == 100 and service.get_state("sku_gin_london_dry").quantity == 3, "Restock preserves current bottle remainder")
	check(menu.inventory["sku_gin_london_dry"] == service.total_remaining("sku_gin_london_dry"), "Menu stock is a Supplies snapshot")
	check(service.purchase("sku_tonic_water") and service.purchase("sku_lime_wedge"), "Required gin and tonic ingredients can be bought")
	var requirements: Dictionary = service.missing_recipe_requirements("gin_and_tonic")
	check(requirements.ready and requirements.ingredients.is_empty() and requirements.equipment.is_empty() and menu.get_recipe("gin_and_tonic").unlocked, "Buying required materials lights the drink with default tools")
	check(service.consume_many({"sku_gin_london_dry": 1600, "sku_tonic_water": 250, "sku_lime_wedge": 20}), "Complete multi-ingredient pour consumes atomically")
	check(menu.get_recipe("gin_and_tonic").unlocked and service.is_unlocked("sku_tonic_water"), "Exhaustion does not erase permanent unlocks")
	check(menu.save_menu([{"id": "gin_and_tonic", "price": 30}], {}), "Unlocked drink can be listed at a player price")
	var restored_wallet := wallet_for("normal")
	var restored_menu := menu_for("normal")
	var restored := service_for("normal", restored_wallet, restored_menu)
	check(restored.total_remaining("sku_gin_london_dry") == 0 and restored.is_owned("tool_jigger") and restored_menu.entries.size() == 1 and restored_wallet.balance == wallet.balance, "Separate reload keeps stock, tool, menu and balance")
	check(restored_menu.reset_game() and restored.reset_game(), "Confirmed component reset succeeds")
	check(restored.total_remaining("sku_tonic_water") == 0 and restored.is_owned("tool_jigger") and restored.is_owned("glass_highball_glass") and restored_menu.unlocked_ids.is_empty(), "Reset empties materials and locks recipes but retains tools and glasses")

func verify_rejected_transactions() -> void:
	var wallet := wallet_for("reject", 300)
	var menu := menu_for("reject")
	var service := service_for("reject", wallet, menu)
	var before: Dictionary = service.serialize()
	var balance: int = wallet.balance
	for args in [["missing", 1], ["glass_highball_glass", 1], ["sku_gin_london_dry", 0], ["sku_gin_london_dry", -1], ["sku_gin_london_dry", 1.5], ["sku_gin_london_dry", 1001], ["sku_gin_london_dry", 4]]:
		check(not service.purchase(args[0], args[1]) and service.serialize() == before and wallet.balance == balance, "Rejected buy changes no wallet or stock: " + str(args))
	for item: Dictionary in service.catalog.list_items():
		if item.storage_mode == "permanent":
			check(not service.purchase(item.id) and service.serialize() == before and wallet.balance == balance and service.is_owned(item.id), "Default tool or glass cannot charge coins: " + item.id)
	check(service.purchase("sku_lime_wedge"), "Atomic consume fixture owns garnish")
	before = service.serialize()
	check(not service.consume_many({"sku_lime_wedge": 1, "sku_white_rum": 1}) and service.serialize() == before, "Insufficient second ingredient leaves first unconsumed")
	wallet.pending = [0, 1, 2]
	balance = wallet.balance
	check(not service.purchase("sku_lime_wedge") and wallet.balance == balance, "Slot settlement blocks purchase")
	wallet.pending = []
	var original_path: String = service.save_path
	service.save_path = original_path.path_join("unwritable.json")
	before = service.serialize()
	check(not service.purchase("sku_lime_wedge") and service.serialize() == before and wallet.balance == balance, "Intent write failure changes neither gold nor stock")
	service.save_path = original_path
	var wallet_path: String = wallet.save_path
	wallet.save_path = wallet_path.path_join("unwritable.json")
	check(not service.purchase("sku_lime_wedge") and service.serialize() == before and wallet.balance == balance and wallet.purchase_receipts.is_empty(), "Failed wallet write cancels intent and preserves both states")
	wallet.save_path = wallet_path

func verify_recipe_unlock_rules() -> void:
	var wallet := wallet_for("recipes", 10000)
	var menu := menu_for("recipes")
	var service := service_for("recipes", wallet, menu)
	for recipe: Dictionary in menu.all_recipes():
		var missing: Dictionary = service.missing_recipe_requirements(recipe.id)
		check(missing.equipment.is_empty(), "Default tools never appear as missing: " + recipe.id)
		for ingredient: Dictionary in recipe.ingredients:
			if not ingredient.get("required", true) or menu._is_ice(ingredient):
				continue
			if not service.is_unlocked(ingredient.sku_id):
				check(service.purchase(ingredient.sku_id), "Required recipe material is purchasable: " + ingredient.sku_id)
		check(menu.get_recipe(recipe.id).unlocked and service.missing_recipe_requirements(recipe.id).ready, "Required materials permanently light each classic: " + recipe.id)
		check(menu.inventory == service.as_recipe_inventory(), "Recipe display uses real Supplies amounts: " + recipe.id)
	check(not service.is_unlocked("sku_lemon_slice") and menu.get_recipe("long_island_iced_tea").unlocked, "Optional lemon decoration does not block unlock")
	var recipe_inventory: Dictionary = service.as_recipe_inventory()
	check(not recipe_inventory.has("sku_ice_standard_cube") and not recipe_inventory.has("sku_ice_crushed"), "Ice never enters the unlock stock snapshot")

func verify_recovery_boundaries() -> void:
	var wallet := wallet_for("recovery")
	var menu := menu_for("recovery")
	var service := InterruptibleSupplies.new()
	objects.append(service)
	service.save_path = temp_dir.path_join("recovery-supplies.json")
	check(service.initialize(wallet, menu), "Recovery fixture initialized")
	service.writes_left = 1
	var starting: int = wallet.balance
	check(service.purchase("sku_lime_wedge", 2), "Receipt commits purchase even when inventory final write is interrupted")
	check(not service.writable and service.total_remaining("sku_lime_wedge") == 40 and wallet.purchase_receipts.size() == 1, "Interrupted settlement retains intent and wallet receipt")
	var resumed_wallet := wallet_for("recovery")
	var resumed := service_for("recovery", resumed_wallet, menu)
	check(resumed.total_remaining("sku_lime_wedge") == 40 and resumed_wallet.balance == starting - 20 and resumed_wallet.purchase_receipts.is_empty(), "Crash after debit recovers exact stock without charging twice")
	check(resumed.load_state() and resumed.total_remaining("sku_lime_wedge") == 40 and resumed_wallet.balance == starting - 20, "Second recovery does not deliver or debit again")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(resumed.save_path))
	check(raw.pending.is_empty(), "Recovered intent is durably cleared")
	var before: Dictionary = resumed.inventory.serialize()
	var candidate := InventoryScript.new()
	check(candidate.restore(before) and candidate.purchase("sku_lime_wedge"), "Prepared-before-debit fixture is valid")
	write_json(resumed.save_path, {"version": 1, "inventory": before, "pending": {"id": "shop-crash-before-debit", "item_id": "sku_lime_wedge", "packages": 1, "cost": 10, "inventory_after": candidate.serialize()}})
	check(resumed.load_state() and resumed.total_remaining("sku_lime_wedge") == 40 and resumed_wallet.balance == starting - 20, "Crash before debit aborts intent without free goods or charge")
	check(resumed_wallet.spend_for_purchase("shop-idempotent-check", 5), "Standalone receipt debits once")
	var debited: int = resumed_wallet.balance
	check(resumed_wallet.spend_for_purchase("shop-idempotent-check", 5) and resumed_wallet.balance == debited, "Repeated receipt does not debit again")
	check(not resumed_wallet.spend_for_purchase("shop-idempotent-check", 6) and resumed_wallet.balance == debited, "Reusing receipt with different amount is rejected")
	check(resumed_wallet.forget_purchase_receipt("shop-idempotent-check"), "Completed receipt can be discarded")

func verify_legacy_and_protection() -> void:
	var wallet := wallet_for("legacy")
	var menu := menu_for("legacy")
	menu.inventory = {"sku_gin_london_dry": 850, "sku_lime_wedge": 7}
	var service := service_for("legacy", wallet, menu)
	check(service.get_state("sku_gin_london_dry").quantity == 2 and service.get_state("sku_gin_london_dry").current_remaining == 100 and service.get_state("sku_lime_wedge").quantity == 7, "Legacy totals migrate into opened package state without resetting progress")
	check(service.save_state(), "Migrated stock can be saved")
	write_json(service.save_path, {"version": 1, "inventory": {"schema_version": 1, "items": {"sku_gin_london_dry": {"unlocked": true, "quantity": 1, "current_remaining": -1}}}, "pending": {}})
	var original := FileAccess.get_file_as_string(service.save_path)
	check(not service.load_state() and not service.writable and not service.purchase("sku_lime_wedge"), "Invalid stock protects save and disables shop")
	check(FileAccess.get_file_as_string(service.save_path) == original, "Protected inventory is never overwritten")
	var old_wallet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(wallet.save_path))
	old_wallet.erase("purchase_receipts")
	write_json(wallet.save_path, old_wallet)
	wallet.load_wallet()
	check(wallet.writable and wallet.purchase_receipts.is_empty(), "Existing wallet without receipts remains compatible")

func legacy_equipment_stock() -> Dictionary:
	var stock := InventoryScript.new()
	check(stock.purchase("sku_gin_london_dry", 2) and stock.consume("sku_gin_london_dry", 650) and stock.purchase("sku_lime_wedge") and stock.consume("sku_lime_wedge", 4), "Legacy tools fixture has partially used bottles and garnish")
	var result: Dictionary = stock.serialize()
	for item: Dictionary in stock.catalog.list_items():
		if item.storage_mode == "permanent":
			result.items[item.id] = {"owned": false, "unlocked": false}
	result.items.erase("tool_bar_spoon")
	return result

func verify_default_equipment_migration() -> void:
	var wallet := wallet_for("default-migration", 777)
	var menu := menu_for("default-migration")
	var path := temp_dir.path_join("default-migration-supplies.json")
	var legacy := legacy_equipment_stock()
	write_json(path, {"version": 1, "inventory": legacy, "pending": {}})
	var original := FileAccess.get_file_as_string(path)
	var failing := InterruptibleSupplies.new()
	objects.append(failing)
	failing.save_path = path
	failing.writes_left = 0
	check(not failing.initialize(wallet, menu) and not failing.writable and wallet.balance == 777 and FileAccess.get_file_as_string(path) == original, "Failed migration write preserves old file and gold, and reports failure")
	var upgraded := service_for("default-migration", wallet, menu)
	check(upgraded.total_remaining("sku_gin_london_dry") == 850 and upgraded.get_state("sku_gin_london_dry").current_remaining == 100 and upgraded.get_state("sku_gin_london_dry").quantity == 2 and upgraded.total_remaining("sku_lime_wedge") == 16, "Tool migration preserves package counts and exact opened-bottle/garnish amounts")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	for item: Dictionary in upgraded.catalog.list_items():
		if item.storage_mode == "permanent":
			check(saved.inventory.items[item.id].owned and saved.inventory.items[item.id].unlocked and upgraded.is_owned(item.id), "Migration durably saves every default tool/glass: " + item.id)
	check(wallet.balance == 777 and wallet.purchase_receipts.is_empty(), "Granting default equipment never debits or credits coins")
	var resumed := service_for("default-migration", wallet, menu)
	check(resumed.total_remaining("sku_gin_london_dry") == 850 and resumed.is_owned("tool_bar_spoon") and wallet.balance == 777, "Normalized equipment and stock survive a second launch")

func verify_legacy_equipment_intent() -> void:
	var wallet := wallet_for("legacy-tool-intent", 777)
	var menu := menu_for("legacy-tool-intent")
	var path := temp_dir.path_join("legacy-tool-intent-supplies.json")
	var before := legacy_equipment_stock()
	var after := before.duplicate(true)
	after.items["tool_jigger"] = {"owned": true, "unlocked": true}
	var transaction := {"id": "shop-legacy-tool-paid", "item_id": "tool_jigger", "packages": 1, "cost": 25, "inventory_after": after}
	write_json(path, {"version": 1, "inventory": before, "pending": transaction})
	check(wallet.spend_for_purchase(transaction.id, transaction.cost), "Previous-version paid tool receipt fixture is durable")
	var paid_balance: int = wallet.balance
	var upgraded := service_for("legacy-tool-intent", wallet, menu)
	check(upgraded.total_remaining("sku_gin_london_dry") == 850 and upgraded.is_owned("tool_jigger") and upgraded.is_owned("tool_bar_spoon") and wallet.balance == paid_balance and wallet.purchase_receipts.is_empty(), "Old paid tool intent recovers with no duplicate charge or stock loss")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(saved.pending.is_empty() and saved.inventory.items["tool_shaker"].owned, "Old tool settlement persists normalized default ownership")
	transaction.id = "shop-legacy-tool-unpaid"
	write_json(path, {"version": 1, "inventory": before, "pending": transaction})
	check(upgraded.load_state() and upgraded.total_remaining("sku_lime_wedge") == 16 and upgraded.is_owned("tool_jigger") and wallet.balance == paid_balance, "Undebited old tool intent is cancelled without charging or altering consumables")

func verify_global_restart() -> void:
	var service := get_node_or_null("/root/Supplies")
	if service == null:
		check(false, "Supplies autoload is registered for the restart integration test")
		return
	SlotWallet.balance = 5000
	SlotWallet.pending = []
	SlotWallet.writable = true
	check(SlotWallet.persist() and MenuCatalog.reset_game() and service.reset_game(), "Isolated global restart fixture begins clean")
	check(service.purchase("sku_gin_london_dry") and service.is_owned("tool_jigger"), "Global fixture contains paid stock and default tool")
	var old_stock := FileAccess.get_file_as_string(service.save_path)
	var backup_root := ProjectSettings.globalize_path(GameSession.save_path).get_base_dir().path_join("backups")
	var prior_backups := DirAccess.get_directories_at(backup_root) if DirAccess.dir_exists_absolute(backup_root) else PackedStringArray()
	TimeManager.advance_minutes(60)
	check(GameSession.restart_game(), "GameSession confirmed restart resets the new shop module")
	check(service.total_remaining("sku_gin_london_dry") == 0 and service.is_owned("tool_jigger") and service.is_owned("glass_balloon_glass"), "Main restart clears stock while keeping free tools and glasses")
	check(SlotWallet.balance == 300 and SlotWallet.purchase_receipts.is_empty() and MenuCatalog.unlocked_ids.is_empty() and MenuCatalog.entries.is_empty(), "Main restart clears wallet, receipts and menu")
	var backed_up := false
	for name in DirAccess.get_directories_at(backup_root):
		if prior_backups.has(name):
			continue
		var saved := backup_root.path_join(name).path_join("4-" + service.save_path.get_file())
		if FileAccess.file_exists(saved) and FileAccess.get_file_as_string(saved) == old_stock:
			backed_up = true
	check(backed_up, "Main restart backs up the shop save before clearing it")
	check(service.load_state() and service.is_owned("glass_balloon_glass") and not service.is_unlocked("sku_gin_london_dry"), "Restart stock remains reset after reloading its file")
