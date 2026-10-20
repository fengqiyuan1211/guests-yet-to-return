extends Node
## The real catalogue and unlocked drinks are separate from the design samples.
signal changed

const MAX_MENU_SIZE := 6
const DEFAULT_CATALOG_PATH := "res://data/drink_catalog.json"
const CocktailDefinitions := preload("res://scripts/cocktail_database.gd")
const DEFAULT_DESIGN := {
	"method": "template", "template": "parchment", "title": "今晚的酒单",
	"subtitle": "致未归的客人", "strokes": [], "ai_image_path": "", "ai_prompt": ""
}

var catalog_path := DEFAULT_CATALOG_PATH
var codex_settings_path := "res://data/codex_settings.json"
var save_path := "user://menu_state.json"
var last_error := ""
var writable := true
var entries: Array = []
var design: Dictionary = DEFAULT_DESIGN.duplicate(true)
var unlocked_ids: Array = []
var seen_recipe_ids: Array = []
var _baseline_research_notifications := false
var inventory: Dictionary = {}
var _recipes: Array = []
var _by_id: Dictionary = {}
var _catalog_ready := false
var _using_finished_catalog := false
var _initial_settings: Dictionary = {}
var _research_service: Node
var _waiting_for_research := false

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
		load_state(true)

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
	_using_finished_catalog = catalog_path == DEFAULT_CATALOG_PATH and data.recipes.is_empty()
	_initial_settings = {}
	var records: Array = data.recipes
	if _using_finished_catalog:
		records = _finished_recipes()
		if records.is_empty():
			return _catalog_error()
		if FileAccess.file_exists(codex_settings_path):
			var settings: Variant = _read_json(codex_settings_path)
			if settings is Dictionary:
				_initial_settings = settings.duplicate(true)
	var next_recipes: Array = []
	var next_by_id: Dictionary = {}
	for recipe in records:
		if _using_finished_catalog:
			var quote:=preload("res://scripts/drink_pricing.gd").quote(recipe)
			if not quote.ok: return _catalog_error()
			recipe["reference_price"]=quote.price
			recipe["pricing"]=quote
			recipe["price_status"]="ingredient_cost_recommendation"
		if not _valid_recipe(recipe) or next_by_id.has(recipe.id):
			return _catalog_error()
		next_recipes.append(recipe.duplicate(true))
		next_by_id[recipe.id] = recipe.duplicate(true)
	_recipes = next_recipes
	_by_id = next_by_id
	_catalog_ready = true
	unlocked_ids = _default_unlocks()
	inventory = _default_inventory()
	last_error = ""
	return true

func _finished_recipes() -> Array:
	# Only the default, empty legacy catalogue uses the canonical cocktail data.
	# A supplied legacy catalogue keeps its own content and unlock defaults.
	var tree := Engine.get_main_loop() as SceneTree
	var database: Node = tree.root.get_node_or_null("CocktailDatabase") if tree != null else null
	var temporary := database == null
	if temporary:
		database = CocktailDefinitions.new()
		if not database.reload_catalog():
			database.free()
			return []
	var result: Array = []
	for cocktail in database.list_cocktails():
		var recipe: Dictionary = cocktail.duplicate(true)
		recipe["category"] = cocktail.type
		recipe["subtitle"] = " · ".join(cocktail.mouthfeel_tags)
		recipe["thumbnail"] = cocktail.image_path
		recipe["tags"] = cocktail.mouthfeel_tags.duplicate()
		for tag in cocktail.flavor_tags:
			if not recipe.tags.has(tag):
				recipe.tags.append(tag)
		recipe["flavor"] = " · ".join(cocktail.flavor_tags)
		# This is a menu editor starting value, not a claimed market price.
		recipe["reference_price"] = cocktail.get("reference_price", 1)
		recipe["price_status"] = "editor_starting_value" if not cocktail.has("reference_price") else "catalog_value"
		recipe["unlocked_by_default"] = false
		var ingredients: Array = []
		var ice: Array = cocktail.get("ice", []).duplicate(true)
		for ingredient in cocktail.ingredients:
			if _is_ice(ingredient):
				ice.append(ingredient.duplicate(true))
			else:
				ingredients.append(ingredient.duplicate(true))
		recipe["ingredients"] = ingredients
		recipe["ice"] = ice
		var standard:=preload("res://scripts/research_data.gd").standard(recipe)
		recipe.design_attributes={}
		for key in preload("res://scripts/research_data.gd").ATTRS:
			recipe.design_attributes[key]=recipe.get(key,0)
			recipe[key]=standard.attributes[key]
		recipe.attributes_version=standard.version
		recipe.attributes_complete=standard.missing.is_empty()
		result.append(recipe)
	for record: Dictionary in preload("res://scripts/research_data.gd").config().get("legendary_recipes", []):
		result.append(record.duplicate(true))
	if temporary:
		database.free()
	return result

func _catalog_error() -> bool:
	_catalog_ready = false
	writable = false
	last_error = "酒谱暂时无法读取，请保留现有记录。"
	return false

func _default_unlocks() -> Array:
	var result: Array = []
	if _using_finished_catalog:
		var initial: Variant = _initial_settings.get("initial_unlocked_ids", [])
		if initial is Array:
			for id in initial:
				if id is String and _by_id.has(id) and not result.has(id):
					result.append(id)
		return result
	for recipe in _recipes:
		if recipe.unlocked_by_default:
			result.append(recipe.id)
	return result

func _default_inventory() -> Dictionary:
	var initial: Variant = _initial_settings.get("initial_inventory", {}) if _using_finished_catalog else {}
	return initial.duplicate(true) if _valid_inventory(initial) else {}

func _valid_inventory(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for sku_id in value:
		if not _text(sku_id, 100, false) or not (value[sku_id] is int or value[sku_id] is float):
			return false
		if not is_finite(float(value[sku_id])) or value[sku_id] < 0:
			return false
	return true

func _is_ice(ingredient: Dictionary) -> bool:
	return str(ingredient.get("sku_id", "")).begins_with("sku_ice_") \
		or str(ingredient.get("ingredient_id", "")).begins_with("ice_") \
		or ingredient.get("use", "") in ["制作冰", "出品冰", "冰", "冰块", "ice"]

func ingredient_available(ingredient: Dictionary) -> bool:
	if _is_ice(ingredient):
		return false
	var available: Variant = inventory.get(ingredient.get("sku_id", ""), 0)
	if not (available is int or available is float) or not is_finite(float(available)) or available <= 0:
		return false
	var needed: Variant = ingredient.get("inventory_amount")
	if (needed is int or needed is float) and is_finite(float(needed)) and needed > 0:
		return available >= needed
	# Dash has no conversion in the source sheet: require stock without inventing ml.
	return ingredient.get("unit", "") == "dash"

func ingredient_progress(cocktail: Dictionary) -> Dictionary:
	var progress := {"owned": 0, "total": 0}
	for ingredient in cocktail.get("ingredients", []):
		if not ingredient is Dictionary or _is_ice(ingredient) or not ingredient.get("required", true):
			continue
		progress.total += 1
		if ingredient_available(ingredient):
			progress.owned += 1
	return progress

func all_recipes() -> Array:
	var result: Array = []
	for recipe in _recipes:
		result.append(get_recipe(recipe.id))
	return result

# Research remains owned by the atomic warehouse/workbench save. The menu only
# stores IDs and prices; official unlocks and sample catalogues stay separate.
func bind_research(service: Node) -> void:
	_research_service = service
	if _waiting_for_research:
		_waiting_for_research = false
		load_state()
	if _baseline_research_notifications:
		var before := seen_recipe_ids.duplicate()
		for recipe in unlocked_recipes():
			if not seen_recipe_ids.has(recipe.id): seen_recipe_ids.append(recipe.id)
		_baseline_research_notifications = false
		# Startup stock sync may already have upgraded the menu schema; keep
		# existing DIY/character recipes acknowledged across the next restart too.
		if seen_recipe_ids != before and writable: save_state()
	# Recover the catalogue half of a tutorial completion interrupted by shutdown
	# or an earlier write failure. Replays and pre-opening legacy profiles opt out.
	if not OpeningFlow.replaying and not OpeningFlow.state.get("legacy",false) and OpeningFlow.state.get("tutorial_status") in ["completed","skipped"] and OpeningFlow.state.get("phase") in ["ending","ready"]:
		unlock_recipe("echo_world")
	changed.emit()

func new_recipe_ids() -> Array:
	var result: Array = []
	for recipe in unlocked_recipes():
		if not seen_recipe_ids.has(recipe.id): result.append(recipe.id)
	return result

func is_recipe_new(id: String) -> bool:
	return not seen_recipe_ids.has(id) and get_recipe(id).get("unlocked",false)

func mark_recipe_seen(id: String) -> bool:
	if not is_recipe_new(id): return true
	if not writable: return false
	var next := seen_recipe_ids.duplicate()
	next.append(id)
	return _commit(entries,design,unlocked_ids,null,next)

func _valid_seen(value: Variant) -> bool:
	if not value is Array: return false
	var ids: Dictionary = {}
	for id in value:
		if not _text(id,100,false) or ids.has(id): return false
		ids[id] = true
	return true

func _diy_recipes() -> Dictionary:
	if not _using_finished_catalog or not is_instance_valid(_research_service) or not _research_service.writable:
		return {}
	return _research_service.state.get("research", {}).get("recipes", {})

func _character_recipes() -> Dictionary:
	if not _using_finished_catalog or not is_instance_valid(_research_service) or not _research_service.writable: return {}
	var records: Dictionary={}
	for raw in preload("res://scripts/research_data.gd").config().legendary_recipes:
		if not raw.get("source_guest","").is_empty():
			var r: Dictionary=raw.duplicate(true)
			var standard:=preload("res://scripts/research_data.gd").standard(r)
			for key in standard.attributes: r[key]=standard.attributes[key]
			r.attributes_complete=standard.missing.is_empty()
			r.unlocked=_research_service.research_state().acquired.has(r.id)
			r.preview_only=false
			_apply_fixed_price(r)
			records[r.id]=r
	return records

func _menu_diy(record: Dictionary) -> Dictionary:
	var recipe := record.duplicate(true)
	var standard:=preload("res://scripts/research_data.gd").standard(record)
	recipe.design_attributes=record.attributes.duplicate(true)
	for key in standard.attributes: recipe[key]=standard.attributes[key]
	recipe.attributes_version=standard.version
	recipe.attributes_complete=standard.missing.is_empty()
	recipe.merge({"category":"DIY", "subtitle":"自创特调", "thumbnail":record.get("image_path", record.get("thumbnail", "")),
		"reference_price":record.get("reference_price",1), "price_status":"ingredient_cost_recommendation",
		"unlocked":true, "unlocked_by_default":false, "preview_only":false,
		"recipe_status":"已保存的 DIY 配方 · v%s" % str(record.get("version",1))}, true)
	_apply_fixed_price(recipe)
	return recipe

func _apply_fixed_price(recipe: Dictionary) -> void:
	var quote := preload("res://scripts/drink_pricing.gd").quote(recipe)
	if quote.ok:
		recipe.reference_price = quote.price
		recipe.pricing = quote
		recipe.price_status = "fixed_ingredient_cost"

func unlocked_recipes() -> Array:
	var result: Array = []
	for recipe in _recipes:
		if unlocked_ids.has(recipe.id):
			result.append(get_recipe(recipe.id))
	for record: Dictionary in _diy_recipes().values():
		result.append(_menu_diy(record))
	for record: Dictionary in _character_recipes().values():
		if record.unlocked: result.append(record)
	return result

func get_recipe(id: String) -> Dictionary:
	if _character_recipes().has(id): return _character_recipes()[id]
	if not _by_id.has(id):
		var record: Dictionary = _diy_recipes().get(id,{})
		return {} if record.is_empty() else _menu_diy(record)
	var recipe: Dictionary = _by_id[id].duplicate(true)
	recipe["unlocked"] = unlocked_ids.has(id)
	var supplies:=get_node_or_null("/root/Supplies")
	if supplies != null and recipe.get("unlock_kind") == "legendary_mastery":
		var picture: Dictionary=supplies.workbench.get("research", {}).get("legendary_images", {}).get(id,{})
		if not picture.is_empty():
			recipe.image_path=picture.path
			recipe.thumbnail=picture.path
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
		if not entry is Dictionary or not entry.get("id") is String or get_recipe(entry.id).is_empty():
			return {"ok": false, "message": "酒单里有尚未收录的酒。"}
		if not available.has(entry.id) and not _diy_recipes().has(entry.id) and not _character_recipes().get(entry.id,{}).get("unlocked",false):
			return {"ok": false, "message": "请先点亮这款酒，再把它加入酒单。"}
		if not _number(entry.get("price"), 1, 9999):
			return {"ok": false, "message": "每杯酒的价格须在 1 到 9999 金币之间。"}
		if seen.has(entry.id):
			if deduplicate:
				continue
			return {"ok": false, "message": "酒单中有重复的酒。"}
		seen[entry.id] = true
		result.append({"id": entry.id, "price": int(get_recipe(entry.id).reference_price)})
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

func load_state(allow_research_wait := false) -> bool:
	if not _catalog_ready:
		return false
	writable = true
	last_error = ""
	if not FileAccess.file_exists(save_path):
		entries = []
		design = DEFAULT_DESIGN.duplicate(true)
		unlocked_ids = _default_unlocks()
		seen_recipe_ids = unlocked_ids.duplicate()
		_baseline_research_notifications = false
		inventory = _default_inventory()
		return true
	var data: Variant = _read_json(save_path)
	if not data is Dictionary or data.get("version") != 1 or not _valid_unlocks(data.get("unlocked_ids")) or not _valid_design(data.get("design")) or not _valid_inventory(data.get("inventory", {})):
		return _state_error()
	if not _valid_seen(data.get("seen_recipe_ids",data.unlocked_ids)): return _state_error()
	var next_unlocked: Array = data.unlocked_ids.duplicate()
	for id in _default_unlocks():
		if not next_unlocked.has(id):
			next_unlocked.append(id)
	# Autoload order loads the menu before the warehouse and research. Block writes
	# until the research service validates its save; never drop custom menu entries
	# or overwrite them with an empty menu during warehouse startup synchronization.
	if allow_research_wait and _using_finished_catalog and data.get("entries") is Array:
		for entry in data.entries:
			if entry is Dictionary and entry.get("id") is String and (entry.id.begins_with("diy_") or entry.id.begins_with("character_")):
				_waiting_for_research = true
				writable = false
				last_error = "正在读取 DIY 配方。"
				return false
	var normalized := _normalize_entries(data.get("entries"), next_unlocked, false)
	if not normalized.ok:
		return _state_error()
	unlocked_ids = next_unlocked
	seen_recipe_ids = data.get("seen_recipe_ids",next_unlocked).duplicate()
	_baseline_research_notifications = not data.has("seen_recipe_ids")
	entries = normalized.entries.duplicate(true)
	design = DEFAULT_DESIGN.duplicate(true)
	design.merge(data.design, true)
	inventory = data.get("inventory", {}).duplicate(true)
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

func update_supply_inventory(next_inventory: Dictionary, purchased_recipe_ids: Array) -> bool:
	# Supplies owns consumable stock. This is a saved display/recipe-check snapshot.
	if not writable or not _catalog_ready or not _valid_inventory(next_inventory):
		return false
	var next_unlocked := unlocked_ids.duplicate()
	for id in purchased_recipe_ids:
		if not id is String or not _by_id.has(id):
			last_error = "原料对应的酒谱暂时无法读取。"
			return false
		if not next_unlocked.has(id):
			next_unlocked.append(id)
	if inventory == next_inventory and unlocked_ids == next_unlocked:
		return true
	return _commit(entries, design, next_unlocked, next_inventory)

func reset_game() -> bool:
	# Called only after the player's confirmed restart and GameSession backup.
	if not _catalog_ready:
		return false
	return _commit([], DEFAULT_DESIGN.duplicate(true), _default_unlocks(), _default_inventory(), _default_unlocks())

func _commit(next_entries: Array, next_design: Dictionary, next_unlocked: Array, next_inventory: Variant = null, next_seen: Variant = null) -> bool:
	var complete_inventory: Variant = inventory if next_inventory == null else next_inventory
	if not _valid_inventory(complete_inventory):
		last_error = "原料记录未能保存，请检查数量后重试。"
		return false
	var snapshot := {"version": 1, "unlocked_ids": next_unlocked.duplicate(true),
		"seen_recipe_ids": seen_recipe_ids.duplicate() if next_seen == null else next_seen.duplicate(),
		"entries": next_entries.duplicate(true), "design": next_design.duplicate(true),
		"inventory": complete_inventory.duplicate(true)}
	if not _atomic_write(snapshot):
		return false
	entries = snapshot.entries
	design = snapshot.design
	unlocked_ids = snapshot.unlocked_ids
	seen_recipe_ids = snapshot.seen_recipe_ids
	inventory = snapshot.inventory
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
		var recipe := get_recipe(entry.id)
		if recipe.is_empty() or not recipe.get("unlocked",false):
			continue
		selected.append({"id": recipe.id, "name": recipe.name,
			"english_name": recipe.get("english_name", ""), "subtitle": recipe.subtitle,
			"category": recipe.category, "tags": recipe.tags.duplicate(),
			"flavor": recipe.get("flavor", ""), "price": entry.price})
	return {"version": 1, "selected_drinks": selected, "title": design.title, "subtitle": design.subtitle}
