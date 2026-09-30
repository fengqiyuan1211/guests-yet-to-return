extends Node
const Catalog := preload("res://scripts/menu_catalog.gd")
var failures: Array[String] = []
var temp_dir := "/tmp/tavern-codex-inventory-%d" % Time.get_ticks_usec()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Fixture can be created")
	if file != null:
		file.store_string(JSON.stringify(value))
		file.close()

func service(state_file := "state.json") -> Node:
	var menu := Catalog.new()
	menu.save_path = temp_dir.path_join(state_file)
	menu.codex_settings_path = temp_dir.path_join("settings.json")
	check(menu.load_catalog(), "Canonical bridge loads")
	check(menu.load_state(), "Player state loads")
	return menu

func _ready() -> void:
	for name in ["SlotWallet", "StoryDialogue", "GameSession", "MenuCatalog"]:
		var singleton := get_node_or_null("/root/" + name)
		if singleton != null and not str(singleton.save_path).begins_with("/tmp/") and not str(singleton.save_path).begins_with("/private/tmp/"):
			push_error("Run this test with isolated --slot-wallet, --dialogue-save and --game-save paths")
			get_tree().quit(2)
			return
	call_deferred("run")

func run() -> void:
	check(DirAccess.make_dir_recursive_absolute(temp_dir) == OK, "Temporary directory created")
	write_json(temp_dir.path_join("settings.json"), {"initial_unlocked_ids": [], "initial_inventory": {}})
	var menu := service()
	var recipes: Array = menu.all_recipes()
	check(recipes.size() == 5 and menu.unlocked_ids.is_empty() and menu.inventory.is_empty(), "All five drinks start locked with no ingredients")
	var counts := {"last_word": 4, "mojito": 7, "gin_and_tonic": 3, "long_island_iced_tea": 8, "manhattan": 4}
	for recipe in recipes:
		check(not recipe.unlocked and recipe.category == "经典" and recipe.thumbnail == recipe.image_path, "Bridge keeps metadata and player lock separate: " + recipe.id)
		check(recipe.reference_price == 1 and recipe.price_status == "editor_starting_value", "Unspecified market price uses editor starting value: " + recipe.id)
		var progress: Dictionary = menu.ingredient_progress(recipe)
		check(progress == {"owned": 0, "total": counts[recipe.id]}, "Required counts exclude ice and optional garnishes: " + recipe.id)
		for ingredient in recipe.ingredients:
			check(not str(ingredient.sku_id).begins_with("sku_ice_"), "Ice is separate from ingredients")
		check(not recipe.ice.is_empty(), "Ice information is retained separately")

	var mojito: Dictionary = menu.get_recipe("mojito")
	var rum: Dictionary = mojito.ingredients[0]
	menu.inventory[rum.sku_id] = rum.inventory_amount - 1
	check(not menu.ingredient_available(rum), "Insufficient stock is unavailable")
	menu.inventory[rum.sku_id] = rum.inventory_amount
	check(menu.ingredient_available(rum) and menu.ingredient_progress(mojito).owned == 1, "Exact stock satisfies one required ingredient")
	var dash := {"sku_id": "sku_dash_test", "unit": "dash", "inventory_amount": null, "amount": 1, "required": true}
	check(not menu.ingredient_available(dash), "Unknown dash conversion still requires stock")
	menu.inventory[dash.sku_id] = 0.001
	check(menu.ingredient_available(dash), "Dash conversion is not invented when stock exists")
	check(menu.unlock_recipe("mojito") and menu.save_menu([{"id": "mojito", "price": 12}], {}), "Player unlock and chosen price can be saved")
	var restored := service()
	check(restored.inventory == menu.inventory and restored.unlocked_ids == ["mojito"] and restored.entries[0].price == 12, "Inventory and unlock persist across reload")
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(menu.save_path))
	old.erase("inventory")
	write_json(temp_dir.path_join("old.json"), old)
	var old_menu := service("old.json")
	check(old_menu.inventory.is_empty() and old_menu.unlocked_ids == ["mojito"] and old_menu.entries.size() == 1, "Version 1 save without inventory preserves unlocks and menu")
	check(restored.reset_game() and restored.inventory.is_empty() and restored.unlocked_ids.is_empty() and restored.entries.is_empty(), "Confirmed restart clears stock, unlocks and menu")
	check(menu.load_state() and menu.inventory.is_empty() and menu.unlocked_ids.is_empty(), "Reset is persisted")

	var invalid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(menu.save_path))
	invalid.inventory = {"sku_bad": -1}
	write_json(temp_dir.path_join("invalid.json"), invalid)
	var damaged := Catalog.new()
	damaged.save_path = temp_dir.path_join("invalid.json")
	check(damaged.load_catalog() and not damaged.load_state() and not damaged.writable, "Negative stock protects the malformed save")
	check(not damaged.save_state(), "Protected save cannot be overwritten")

	write_json(temp_dir.path_join("empty.json"), {"version": 1, "recipes": []})
	var isolated := Catalog.new()
	isolated.catalog_path = temp_dir.path_join("empty.json")
	check(isolated.load_catalog() and isolated.all_recipes().is_empty(), "Explicit empty test catalogue does not load canonical drinks")
	var legacy := {"id": "legacy", "name": "老酒谱", "category": "特调", "subtitle": "", "thumbnail": "", "tags": [], "reference_price": 20, "unlocked_by_default": true}
	write_json(temp_dir.path_join("legacy.json"), {"version": 1, "recipes": [legacy]})
	isolated.catalog_path = temp_dir.path_join("legacy.json")
	check(isolated.load_catalog() and isolated.all_recipes().size() == 1 and isolated.unlocked_ids == ["legacy"], "Legacy records and their defaults retain priority")
	for value in [menu, restored, old_menu, damaged, isolated]:
		value.free()
	for file_name in DirAccess.get_files_at(temp_dir):
		DirAccess.remove_absolute(temp_dir.path_join(file_name))
	DirAccess.remove_absolute(temp_dir)
	print("CODEX INVENTORY: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
