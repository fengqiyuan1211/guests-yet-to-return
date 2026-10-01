extends RefCounted
## Explicit inventory model, ready for a future shop. No automatic live-save writes.

const CatalogScript = preload("res://scripts/supply_catalog.gd")
const INITIAL_PATH := "res://data/supplies/initial_state.json"
var catalog: RefCounted
var last_error := ""
var _states: Dictionary = {}

func _init() -> void:
	catalog = CatalogScript.new()
	reset()

func reset() -> void:
	var template: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INITIAL_PATH))
	_states = template.get("items", {}).duplicate(true)
	_own_default_equipment()
	last_error = ""

func _own_default_equipment() -> void:
	# Workbench tools and serving glasses are supplied with the bar.
	for item: Dictionary in catalog.list_items():
		if item.storage_mode == "permanent":
			_states[item.id] = {"unlocked": true, "owned": true}

func get_state(id: String) -> Dictionary:
	return _states.get(id, {}).duplicate(true)

func is_unlocked(id: String) -> bool:
	return bool(_states.get(id, {}).get("unlocked", false))

func total_remaining(id: String) -> float:
	var item: Dictionary = catalog.get_item(id)
	var state := get_state(id)
	if item.is_empty() or state.is_empty():
		return 0.0
	match item.storage_mode:
		"container":
			return float(state.current_remaining) + maxi(0, int(state.quantity) - 1) * float(item.package.container_capacity)
		"quantity":
			return float(state.quantity)
		"permanent":
			return 1.0 if state.owned else 0.0
	return 0.0

func purchase(id: String, packages := 1) -> bool:
	# Caller handles currency/payment. This only records a completed purchase.
	var item: Dictionary = catalog.get_item(id)
	if item.is_empty() or packages <= 0:
		last_error = "购买内容或数量无效。"
		return false
	if item.storage_mode == "permanent":
		last_error = "酒馆已经备好这些器材和酒杯。"
		return false
	var state := get_state(id)
	match item.storage_mode:
		"container":
			if int(state.quantity) == 0:
				state.current_remaining = float(item.package.container_capacity)
			state.quantity = int(state.quantity) + packages
		"quantity":
			state.quantity = int(state.quantity) + packages * int(item.package.purchase_quantity)
		"permanent":
			state.owned = true
	state.unlocked = true
	_states[id] = state
	last_error = ""
	return true

func consume(id: String, amount: float) -> bool:
	var item: Dictionary = catalog.get_item(id)
	if item.is_empty() or item.storage_mode == "permanent" or not is_finite(amount) or amount <= 0:
		last_error = "消耗内容或数量无效。"
		return false
	if item.storage_mode == "quantity" and amount != floor(amount):
		last_error = "这类物品按整件消耗。"
		return false
	if amount > total_remaining(id):
		last_error = "剩余原料不足。"
		return false
	var state := get_state(id)
	if item.storage_mode == "quantity":
		state.quantity = int(state.quantity) - int(amount)
	else:
		var left := amount
		var capacity := float(item.package.container_capacity)
		while left > 0.0:
			var remaining := float(state.current_remaining)
			if left < remaining:
				state.current_remaining = remaining - left
				left = 0.0
			else:
				left -= remaining
				state.quantity = int(state.quantity) - 1
				state.current_remaining = capacity if int(state.quantity) > 0 else 0.0
	_states[id] = state
	last_error = ""
	return true

func as_recipe_inventory() -> Dictionary:
	# Compatible snapshot for current recipe checks keyed by sku_id.
	var result: Dictionary = {}
	for item: Dictionary in catalog.list_items():
		if item.kind == "ingredient":
			result[item.id] = total_remaining(item.id)
	return result

func serialize() -> Dictionary:
	return {"schema_version": 1, "items": _states.duplicate(true)}

func restore(data: Variant) -> bool:
	if not data is Dictionary or data.get("schema_version") != 1 or not data.get("items") is Dictionary:
		last_error = "库存存档无法读取。"
		return false
	var candidate := _states.duplicate(true)
	for item: Dictionary in catalog.list_items():
		var id: String = item.id
		if item.storage_mode == "permanent":
			candidate[id] = {"unlocked": true, "owned": true}
			continue
		if not data.items.has(id):
			# New catalogue entries start locked, even if this object held old stock.
			candidate[id] = {"unlocked": false}
			if item.storage_mode == "permanent":
				candidate[id].owned = false
			else:
				candidate[id].quantity = 0
				if item.storage_mode == "container":
					candidate[id].current_remaining = 0.0
			continue
		var value: Variant = data.items[id]
		if not value is Dictionary or not value.get("unlocked") is bool:
			last_error = "库存解锁状态无效。"
			return false
		var clean := {"unlocked": value.unlocked}
		if item.storage_mode == "permanent":
			if not value.get("owned") is bool or (value.owned and not value.unlocked):
				last_error = "器具拥有状态无效。"
				return false
			clean.owned = value.owned
		else:
			var quantity: Variant = value.get("quantity")
			if not (quantity is int or quantity is float) or not is_finite(float(quantity)) or float(quantity) != floor(float(quantity)) or quantity < 0:
				last_error = "库存数量无效。"
				return false
			clean.quantity = int(quantity)
			if quantity > 0 and not value.unlocked:
				last_error = "有库存的原料应已解锁。"
				return false
			if item.storage_mode == "container":
				var remaining: Variant = value.get("current_remaining")
				if not (remaining is int or remaining is float) or not is_finite(float(remaining)) or remaining < 0 or remaining > float(item.package.container_capacity) or (quantity == 0 and remaining != 0) or (quantity > 0 and remaining <= 0):
					last_error = "当前包装余量无效。"
					return false
				clean.current_remaining = float(remaining)
		candidate[id] = clean
	_states = candidate
	last_error = ""
	return true

func save_to(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_error = "库存暂时无法保存。"
		return false
	file.store_string(JSON.stringify(serialize(), "\t"))
	last_error = ""
	return true

func load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		last_error = "库存存档不存在。"
		return false
	return restore(JSON.parse_string(FileAccess.get_file_as_string(path)))
