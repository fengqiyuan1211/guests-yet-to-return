extends Node
const Catalog := preload("res://scripts/menu_catalog.gd")
var failures: Array[String] = []
var temp_dir := "/tmp/tavern-menu-contract-%d" % Time.get_ticks_usec()

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

func fixture() -> Array:
	var result: Array = []
	for index in range(1, 8):
		result.append({"id": "test_%d" % index, "name": "测试酒 %d" % index,
			"subtitle": "仅测试", "category": "短饮", "tags": ["清爽"],
			"reference_price": 30, "thumbnail": "", "unlocked_by_default": index == 1,
			"english_name": "Test %d" % index, "flavor": "测试风味"})
	return result

func service(state_file: String = "state.json") -> Node:
	var value := Catalog.new()
	value.catalog_path = temp_dir.path_join("catalog.json")
	value.save_path = temp_dir.path_join(state_file)
	check(value.load_catalog(), "Test catalogue loads")
	check(value.load_state(), "Initial test state loads")
	return value

func _ready() -> void:
	# Even autoloads must be isolated before this scene is run.
	for name in ["SlotWallet", "StoryDialogue", "GameSession", "MenuCatalog"]:
		var singleton := get_node_or_null("/root/" + name)
		if singleton != null and not str(singleton.save_path).begins_with("/tmp/") and not str(singleton.save_path).begins_with("/private/tmp/"):
			push_error("Run this test with isolated --slot-wallet, --dialogue-save and --game-save paths")
			get_tree().quit(2)
			return
	call_deferred("run")

func run() -> void:
	check(DirAccess.make_dir_recursive_absolute(temp_dir) == OK, "Temporary directory created")
	var official := Catalog.new()
	official.save_path = temp_dir.path_join("official.json")
	check(official.load_catalog() and official.load_state(), "Official canonical catalogue is valid")
	check(official.all_recipes().size() == 5 and official.unlocked_recipes().is_empty(), "Five canonical drinks are listed and remain locked")
	var samples: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/menu_samples.json"))
	check(samples is Dictionary and samples.get("preview_only") == true and samples.get("recipes", []).size() == 6, "Six samples explicitly remain preview-only")
	check(official.menu_for_ai().selected_drinks.is_empty(), "Samples never enter the AI order/menu payload")
	check(not official.unlock_recipe("sample_mojito"), "Sample identifier cannot be unlocked")
	official.free()

	write_json(temp_dir.path_join("catalog.json"), {"version": 1, "recipes": fixture()})
	var menu := service()
	var notifications := [0]
	menu.changed.connect(func(): notifications[0] += 1)
	check(menu.unlocked_ids == ["test_1"], "Only declared default drink is unlocked")
	check(not menu.save_menu([{"id": "test_2", "price": 25}], {}), "Locked drink cannot be sold")
	check(not FileAccess.file_exists(menu.save_path), "Rejected menu does not create a save")
	check(not menu.unlock_recipe("unknown"), "Unknown recipe is rejected")
	check(menu.unlock_recipe("test_2"), "Explicit unlock is persisted")
	var notify_count: int = notifications[0]
	check(menu.unlock_recipe("test_2") and notifications[0] == notify_count, "Repeated unlock is idempotent")
	var draft := [{"id": "test_1", "price": 33.5}, {"id": "test_1", "price": 44}, {"id": "test_2", "price": 20}]
	var drawing := {"method": "draw", "title": "今晚来一杯", "ai_prompt": "西部暖色纸张",
		"strokes": [{"color": "#68452aff", "width": 4, "points": [[0.1, 0.2], [0.8, 0.9]]}]}
	check(menu.save_menu(draft, drawing), "Valid menu and drawing save")
	check(menu.entries.size() == 2 and menu.entries[0].price == 33.5, "Duplicates collapse in order and keep first price")
	draft[0].price = 999
	drawing.strokes[0].points[0][0] = 0.7
	check(menu.entries[0].price == 33.5 and menu.design.strokes[0].points[0][0] == 0.1, "Saved state does not alias draft data")
	var copy: Dictionary = menu.get_recipe("test_1")
	copy.tags.append("不该写回")
	check(menu.get_recipe("test_1").tags == ["清爽"], "Recipe getter returns a deep copy")
	var before := FileAccess.get_file_as_string(menu.save_path)
	for price in [0, -1, 10000, NAN, INF, "30", null]:
		check(not menu.save_menu([{"id": "test_1", "price": price}], {}), "Invalid price rejected: %s" % str(price))
		check(FileAccess.get_file_as_string(menu.save_path) == before and menu.entries[0].price == 33.5, "Failed validation preserves disk and memory")
	check(not menu.save_menu([{"id": "test_1", "price": 30}], {"title": " "}), "Blank title rejected")
	check(not menu.save_menu([{"id": "test_1", "price": 30}], {"method": "invalid"}), "Unknown design method rejected")
	check(not menu.save_menu([{"id": "test_1", "price": 30}], {"ai_prompt": "x".repeat(601)}), "Oversize AI prompt rejected")
	check(not menu.save_menu([{"id": "test_1", "price": 30}], {"strokes": [{"color": "bad color", "width": 4, "points": [[0, 0]]}]}), "Malformed stroke rejected")
	check(not menu.save_menu([{"id": "test_1", "price": 30}], {"strokes": [{"color": "#ffffff", "width": 4, "points": [[-0.1, 0]]}]}), "Out-of-bounds stroke rejected")
	check(FileAccess.get_file_as_string(menu.save_path) == before, "All rejected designs preserve existing save")
	var restored := service()
	check(restored.entries == JSON.parse_string(JSON.stringify(menu.entries, "", true, true)) and restored.design == JSON.parse_string(JSON.stringify(menu.design, "", true, true)) and restored.unlocked_ids == menu.unlocked_ids, "Reload restores exact menu, drawing and unlocks")
	var ai: Dictionary = menu.menu_for_ai()
	check(ai.selected_drinks.size() == 2 and ai.selected_drinks[0].price == 33.5 and ai.selected_drinks[0].flavor == "测试风味", "AI payload contains only selected drinks and actual prices")
	ai.selected_drinks[0].tags.append("copy")
	check(menu.get_recipe("test_1").tags == ["清爽"], "AI payload does not alias catalogue")
	for index in range(3, 8):
		check(menu.unlock_recipe("test_%d" % index), "Additional explicit unlock")
	var seven: Array = []
	for index in range(1, 8):
		seven.append({"id": "test_%d" % index, "price": 30})
	check(not menu.save_menu(seven, {}), "Seventh distinct drink rejected")
	seven.pop_back()
	check(menu.save_menu(seven, {"template": "nocturne"}), "Six drinks can be saved")
	before = FileAccess.get_file_as_string(menu.save_path)
	var previous_entries: Array = menu.entries.duplicate(true)
	var actual_path: String = menu.save_path
	menu.save_path = actual_path.path_join("cannot-write-inside-file.json")
	check(not menu.save_menu([], {"title": "不会落盘"}), "Filesystem failure is reported")
	check(menu.entries == previous_entries and FileAccess.get_file_as_string(actual_path) == before, "Write failure rolls back all menu changes")
	menu.save_path = actual_path

	var failure_service := service("unlock-failure.json")
	failure_service.save_path = actual_path.path_join("cannot-write.json")
	check(not failure_service.unlock_recipe("test_2") and failure_service.unlocked_ids == ["test_1"], "Failed unlock save does not change memory")
	failure_service.free()

	var bad_path := temp_dir.path_join("damaged.json")
	var bad_file := FileAccess.open(bad_path, FileAccess.WRITE)
	bad_file.store_string("{broken unfinished save")
	bad_file.close()
	var damaged := Catalog.new()
	damaged.catalog_path = temp_dir.path_join("catalog.json")
	damaged.save_path = bad_path
	check(damaged.load_catalog() and not damaged.load_state() and not damaged.writable, "Broken JSON switches save into protected mode")
	check(not damaged.save_menu([], {}) and not damaged.unlock_recipe("test_2") and not damaged.save_state(), "Normal actions cannot overwrite broken save")
	check(FileAccess.get_file_as_string(bad_path) == "{broken unfinished save", "Broken save bytes are retained")
	check(damaged.reset_game() and damaged.writable and damaged.entries.is_empty() and damaged.unlocked_ids == ["test_1"], "Confirmed restart can deliberately restore defaults")
	var invalid_state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(bad_path))
	invalid_state.entries = [{"id": "test_2", "price": 30}]
	write_json(bad_path, invalid_state)
	before = FileAccess.get_file_as_string(bad_path)
	check(not damaged.load_state() and not damaged.writable, "Saved locked drink is rejected")
	check(FileAccess.get_file_as_string(bad_path) == before, "Invalid semantic save is retained")
	check(menu.reset_game() and menu.entries.is_empty() and menu.design == Catalog.DEFAULT_DESIGN and menu.unlocked_ids == ["test_1"], "Restart clears menu, art and unlocks to defaults")
	check(restored.load_state() and restored.entries.is_empty() and restored.unlocked_ids == ["test_1"], "Restart persists across reload")
	menu.free()
	restored.free()
	damaged.free()
	for file_name in DirAccess.get_files_at(temp_dir):
		DirAccess.remove_absolute(temp_dir.path_join(file_name))
	DirAccess.remove_absolute(temp_dir)
	print("MENU CATALOG: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
