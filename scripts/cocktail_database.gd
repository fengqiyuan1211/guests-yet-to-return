extends Node
## Finished cocktail definitions. Inventory and player unlocks belong to player state.

const CATALOG_PATH := "res://data/cocktails/catalog.json"
const SCORE_FIELDS := ["alcohol_intensity", "sweetness", "sourness", "bitterness"]

var last_error := ""
var source: Dictionary = {}
var _records: Array = []
var _by_id: Dictionary = {}
var _textures: Dictionary = {}

func _ready() -> void:
	reload_catalog()

func _valid_text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

func _valid_record(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for field in ["id", "name", "english_name", "image_path"]:
		if not _valid_text(value.get(field)):
			return false
	if value.get("type") not in ["经典", "特调"] or not str(value.image_path).begins_with("res://"):
		return false
	for field in SCORE_FIELDS:
		var score: Variant = value.get(field)
		if not (score is int or score is float) or not is_finite(float(score)) or score < 0 or score > 100:
			return false
	for field in ["mouthfeel_tags", "flavor_tags"]:
		if not value.get(field) is Array:
			return false
		for tag in value[field]:
			if not _valid_text(tag):
				return false
	if not value.get("ingredients") is Array or value.ingredients.is_empty():
		return false
	for ingredient in value.ingredients:
		if not ingredient is Dictionary:
			return false
		for field in ["id", "sku_id", "name", "unit", "use"]:
			if not _valid_text(ingredient.get(field)):
				return false
		var amount: Variant = ingredient.get("amount")
		if not (amount is int or amount is float) or not is_finite(float(amount)) or amount <= 0:
			return false
		if not ingredient.get("required") is bool:
			return false
	# Presentation fields are compatible extensions to v1, checked before UI use.
	for field in ["story", "preparation", "decoration_id", "glass"]:
		if value.has(field) and not value[field] is String:
			return false
	if value.has("codex_order"):
		var order: Variant = value.codex_order
		if not (order is int or order is float) or not is_finite(float(order)) or order < 1 or order != floor(order):
			return false
	if value.has("display_equipment"):
		if not value.display_equipment is Array:
			return false
		for tool in value.display_equipment:
			if not _valid_text(tool):
				return false
	if value.has("ice"):
		if not value.ice is Array:
			return false
		for ice in value.ice:
			if not ice is Dictionary or not _valid_text(ice.get("name")) or not _valid_text(ice.get("unit")):
				return false
			var amount: Variant = ice.get("amount")
			if not (amount is int or amount is float) or not is_finite(float(amount)) or amount <= 0:
				return false
	if value.has("display_steps"):
		if not value.display_steps is Array:
			return false
		for step in value.display_steps:
			if not step is Dictionary or not _valid_text(step.get("operation")) or not _valid_text(step.get("instruction")):
				return false
			var number: Variant = step.get("number")
			if not (number is int or number is float) or not is_finite(float(number)) or number < 1 or number != floor(number):
				return false
	return true

func reload_catalog() -> bool:
	if not FileAccess.file_exists(CATALOG_PATH):
		last_error = "鸡尾酒资料暂时无法读取。"
		return false
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(CATALOG_PATH)) != OK:
		last_error = "鸡尾酒资料格式有误。"
		return false
	var data: Variant = parser.data
	if not data is Dictionary or data.get("schema_version") != 1 or not data.get("cocktails") is Array:
		last_error = "鸡尾酒资料版本无法读取。"
		return false
	var next_records: Array = []
	var next_by_id: Dictionary = {}
	for record in data.cocktails:
		if not _valid_record(record) or next_by_id.has(record.id):
			last_error = "鸡尾酒资料中存在缺失或重复内容。"
			return false
		next_records.append(record.duplicate(true))
		next_by_id[record.id] = record.duplicate(true)
	_records = next_records
	_by_id = next_by_id
	_textures.clear()
	source = data.get("source", {}).duplicate(true)
	last_error = ""
	return true

func list_cocktails(cocktail_type := "") -> Array:
	var result: Array = []
	for record in _records:
		if cocktail_type.is_empty() or record.type == cocktail_type:
			result.append(record.duplicate(true))
	return result

func get_cocktail(id: String) -> Dictionary:
	if not _by_id.has(id):
		return {}
	return _by_id[id].duplicate(true)

func has_cocktail(id: String) -> bool:
	return _by_id.has(id)

func get_image(id: String) -> Texture2D:
	if not _by_id.has(id):
		return null
	if _textures.has(id):
		return _textures[id]
	var image_path: String = _by_id[id].image_path
	if not ResourceLoader.exists(image_path):
		return null
	var texture := load(image_path) as Texture2D
	if texture != null:
		_textures[id] = texture
	return texture
