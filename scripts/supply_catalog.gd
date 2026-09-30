extends RefCounted
## Separate product definitions; player ownership lives in SupplyInventory.

const CATALOG_PATH := "res://data/supplies/catalog.json"
var last_error := ""
var _items: Dictionary = {}
var _ice: Array = []

func _init() -> void:
	reload_catalog()

func reload_catalog() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary or parsed.get("schema_version") != 1 or not parsed.get("items") is Array:
		last_error = "原料与器具资料无法读取。"
		return false
	var next_items: Dictionary = {}
	for item: Variant in parsed.items:
		if not item is Dictionary or str(item.get("id", "")).is_empty() or next_items.has(item.id):
			last_error = "原料与器具编号缺失或重复。"
			return false
		if item.get("storage_mode") not in ["container", "quantity", "permanent"]:
			last_error = "库存方式无法读取。"
			return false
		if item.storage_mode == "container" and float(item.get("package", {}).get("container_capacity", 0)) <= 0:
			last_error = "原料包装容量缺失。"
			return false
		next_items[item.id] = item.duplicate(true)
	_items = next_items
	_ice = parsed.get("ice", []).duplicate(true)
	last_error = ""
	return true

func get_item(id: String) -> Dictionary:
	return _items.get(id, {}).duplicate(true)

func list_items(category := "") -> Array:
	var result: Array = []
	for item: Dictionary in _items.values():
		if category.is_empty() or item.category == category:
			result.append(item.duplicate(true))
	return result

func list_ice() -> Array:
	return _ice.duplicate(true)

func get_texture(id: String) -> Texture2D:
	var item := get_item(id)
	if item.is_empty():
		return null
	return load(item.texture_resource_path) as Texture2D
