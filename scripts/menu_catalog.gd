extends Node
## The real catalogue and unlocked drinks are separate from the design samples.
signal changed

const MAX_MENU_SIZE := 6
const DEFAULT_DESIGN := {
	"method": "template", "template": "parchment", "title": "今晚的酒单",
	"subtitle": "致未归的客人", "strokes": [], "ai_image_path": "", "ai_prompt": ""
}

var catalog_path := "res://data/drink_catalog.json"
var save_path := "user://menu_state.json"
var last_error := ""
var writable := true
var entries: Array = []
var design: Dictionary = DEFAULT_DESIGN.duplicate(true)
var unlocked_ids: Array = []
var _recipes: Array = []
var _by_id: Dictionary = {}
var _catalog_ready := false

func _ready() -> void:
	# Match existing isolated test saves; explicit menu paths take precedence.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dialogue-save="):
			save_path = arg.trim_prefix("--dialogue-save=") + ".menu"
		elif arg.begins_with("--slot-wallet=") and save_path == "user://menu_state.json":
			save_path = arg.trim_prefix("--slot-wallet=") + ".menu"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--game-save="):
			save_path = arg.trim_prefix("--game-save=") + ".menu"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--menu-save="):
			save_path = arg.trim_prefix("--menu-save=")
	if load_catalog():
		load_state()

func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum

func _text(value: Variant, maximum: int, allow_empty := true) -> bool:
	return value is String and value.length() <= maximum and (allow_empty or not value.strip_edges().is_empty())

func _valid_recipe(recipe: Variant) -> bool:
	if not recipe is Dictionary:
		return false
	for field in ["id", "name", "category"]:
		if not _text(recipe.get(field), 100, false):
			return false
	if recipe.id != recipe.id.strip_edges() or not _text(recipe.get("subtitle"), 180) or not _text(recipe.get("thumbnail"), 512):
		return false
	if not _number(recipe.get("reference_price"), 1, 9999) or not recipe.get("unlocked_by_default") is bool:
		return false
	if not recipe.get("tags") is Array or recipe.tags.size() > 20:
		return false
	for tag in recipe.tags:
		if not _text(tag, 40, false):
			return false
	for field in ["english_name", "flavor"]:
		if recipe.has(field) and not _text(recipe[field], 180):
			return false
	return true

func _read_json(path: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return parser.data

func load_catalog() -> bool:
	var data: Variant = _read_json(catalog_path)
	if not data is Dictionary or data.get("version") != 1 or not data.get("recipes") is Array:
		return _catalog_error()
	var next_recipes: Array = []
	var next_by_id: Dictionary = {}
	for recipe in data.recipes:
		if not _valid_recipe(recipe) or next_by_id.has(recipe.id):
			return _catalog_error()
		next_recipes.append(recipe.duplicate(true))
		next_by_id[recipe.id] = recipe.duplicate(true)
	_recipes = next_recipes
	_by_id = next_by_id
	_catalog_ready = true
	unlocked_ids = _default_unlocks()
	last_error = ""
	return true

func _catalog_error() -> bool:
	_catalog_ready = false
	writable = false
	last_error = "酒谱暂时无法读取，请保留现有记录。"
	return false

func _default_unlocks() -> Array:
	var result: Array = []
	for recipe in _recipes:
		if recipe.unlocked_by_default:
			result.append(recipe.id)
	return result

func all_recipes() -> Array:
	var result: Array = []
	for recipe in _recipes:
		result.append(get_recipe(recipe.id))
	return result

func unlocked_recipes() -> Array:
	var result: Array = []
	for recipe in _recipes:
		if unlocked_ids.has(recipe.id):
			result.append(get_recipe(recipe.id))
	return result

func get_recipe(id: String) -> Dictionary:
	if not _by_id.has(id):
		return {}
	var recipe: Dictionary = _by_id[id].duplicate(true)
	recipe["unlocked"] = unlocked_ids.has(id)
	return recipe

func unlock_recipe(id: String) -> bool:
	if not writable or not _catalog_ready:
		return false
	if not _by_id.has(id):
		last_error = "酒谱中还没有这款酒。"
		return false
	if unlocked_ids.has(id):
		last_error = ""
		return true
	var next_unlocked := unlocked_ids.duplicate()
	next_unlocked.append(id)
	return _commit(entries, design, next_unlocked)

func _normalize_entries(value: Variant, available: Array, deduplicate: bool) -> Dictionary:
	if not value is Array:
		return {"ok": false, "message": "酒单内容无法读取。"}
	var result: Array = []
	var seen: Dictionary = {}
	for entry in value:
		if not entry is Dictionary or not entry.get("id") is String or not _by_id.has(entry.id):
			return {"ok": false, "message": "酒单里有尚未收录的酒。"}
		if not available.has(entry.id):
			return {"ok": false, "message": "请先点亮这款酒，再把它加入酒单。"}
		if not _number(entry.get("price"), 1, 9999):
			return {"ok": false, "message": "每杯酒的价格须在 1 到 9999 金币之间。"}
		if seen.has(entry.id):
			if deduplicate:
				continue
			return {"ok": false, "message": "酒单中有重复的酒。"}
		seen[entry.id] = true
		result.append({"id": entry.id, "price": entry.price})
	if result.size() > MAX_MENU_SIZE:
		return {"ok": false, "message": "一张酒单最多上架六款酒。"}
	return {"ok": true, "entries": result}

func _valid_design(value: Variant) -> bool:
	if not value is Dictionary or not value.get("method") in ["template", "draw", "ai"] or not value.get("template") in ["parchment", "nocturne"]:
		return false
	if not _text(value.get("title"), 48, false) or not _text(value.get("subtitle"), 96) or not _text(value.get("ai_image_path"), 1024):
		return false
	if not _text(value.get("ai_prompt", ""), 600):
		return false
	if not value.get("strokes") is Array or value.strokes.size() > 500:
		return false
	var point_count := 0
	for stroke in value.strokes:
		if not stroke is Dictionary or not stroke.get("color") is String or not Color.html_is_valid(stroke.color):
			return false
		if not _number(stroke.get("width"), 1, 64) or not stroke.get("points") is Array or stroke.points.is_empty():
			return false
		point_count += stroke.points.size()
		if point_count > 20000:
			return false
		for point in stroke.points:
			if not point is Array or point.size() != 2 or not _number(point[0], 0, 1) or not _number(point[1], 0, 1):
				return false
	return true

func _valid_unlocks(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for id in value:
		if not id is String or not _by_id.has(id) or seen.has(id):
			return false
		seen[id] = true
	return true

func load_state() -> bool:
	if not _catalog_ready:
		return false
	writable = true
	last_error = ""
	if not FileAccess.file_exists(save_path):
		entries = []
		design = DEFAULT_DESIGN.duplicate(true)
		unlocked_ids = _default_unlocks()
		return true
	var data: Variant = _read_json(save_path)
	if not data is Dictionary or data.get("version") != 1 or not _valid_unlocks(data.get("unlocked_ids")) or not _valid_design(data.get("design")):
		return _state_error()
	var next_unlocked: Array = data.unlocked_ids.duplicate()
	for id in _default_unlocks():
		if not next_unlocked.has(id):
			next_unlocked.append(id)
	var normalized := _normalize_entries(data.get("entries"), next_unlocked, false)
	if not normalized.ok:
		return _state_error()
	unlocked_ids = next_unlocked
	entries = normalized.entries.duplicate(true)
	design = DEFAULT_DESIGN.duplicate(true)
	design.merge(data.design, true)
	return true

func _state_error() -> bool:
	writable = false
	last_error = "上次的酒单未能读取，原记录已保留。"
	return false

func save_menu(next_entries: Array, next_design: Dictionary) -> bool:
	if not writable or not _catalog_ready:
		return false
	var normalized := _normalize_entries(next_entries, unlocked_ids, true)
	if not normalized.ok:
		last_error = normalized.message
		return false
	var complete_design := DEFAULT_DESIGN.duplicate(true)
	complete_design.merge(next_design, true)
	if not _valid_design(complete_design):
		last_error = "酒单样式未能保存，请检查文字和画稿后重试。"
		return false
	return _commit(normalized.entries, complete_design, unlocked_ids)

func save_state() -> bool:
	if not writable or not _catalog_ready or not _valid_unlocks(unlocked_ids):
		return false
	return save_menu(entries, design)

func reset_game() -> bool:
	# Called only after the player's confirmed restart and GameSession backup.
	if not _catalog_ready:
		return false
	return _commit([], DEFAULT_DESIGN.duplicate(true), _default_unlocks())

func _commit(next_entries: Array, next_design: Dictionary, next_unlocked: Array) -> bool:
	var snapshot := {"version": 1, "unlocked_ids": next_unlocked.duplicate(true),
		"entries": next_entries.duplicate(true), "design": next_design.duplicate(true)}
	if not _atomic_write(snapshot):
		return false
	entries = snapshot.entries
	design = snapshot.design
	unlocked_ids = snapshot.unlocked_ids
	writable = true
	last_error = ""
	changed.emit()
	return true

func _atomic_write(snapshot: Dictionary) -> bool:
	var temporary := save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "酒单未能保存，请检查存储空间后重试。"
		return false
	file.store_string(JSON.stringify(snapshot, "", true, true))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		last_error = "酒单未能保存，请重试。"
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(save_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		last_error = "酒单未能保存，请重试。"
		return false
	return true

func menu_for_ai() -> Dictionary:
	var selected: Array = []
	for entry in entries:
		if not _by_id.has(entry.id) or not unlocked_ids.has(entry.id):
			continue
		var recipe := get_recipe(entry.id)
		selected.append({"id": recipe.id, "name": recipe.name,
			"english_name": recipe.get("english_name", ""), "subtitle": recipe.subtitle,
			"category": recipe.category, "tags": recipe.tags.duplicate(),
			"flavor": recipe.get("flavor", ""), "price": entry.price})
	return {"version": 1, "selected_drinks": selected, "title": design.title, "subtitle": design.subtitle}
