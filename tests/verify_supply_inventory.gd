extends Node
## Uses only /tmp files; never imports art resources or touches live player saves.

const InventoryScript := preload("res://scripts/supply_inventory.gd")
const SupplyCatalogScript := preload("res://scripts/supply_catalog.gd")
const GIN := "sku_gin_london_dry"
const LIME := "sku_lime_wedge"
const SHAKER := "tool_shaker"
var failures: Array[String] = []
var checks := 0
var temp_dir := "/tmp/tavern-supply-contract-%d" % Time.get_ticks_usec()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func same_state(a: Dictionary, b: Dictionary) -> bool:
	# JSON reads numbers as float; restore normalizes whole counts to int.
	# Compare their serialized values after parsing rather than 0 vs 0.0 text.
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func write_json(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "Test fixture can be written")
	if file != null:
		file.store_string(JSON.stringify(data))
		file.close()

func _ready() -> void:
	for name in ["SlotWallet", "StoryDialogue", "GameSession", "MenuCatalog", "Supplies"]:
		var singleton := get_node_or_null("/root/" + name)
		if singleton != null and not str(singleton.save_path).begins_with("/tmp/") and not str(singleton.save_path).begins_with("/private/tmp/"):
			push_error("Run with isolated --slot-wallet, --dialogue-save, --game-save and --menu-save paths")
			get_tree().quit(2)
			return
	TimeManager.set_process(false)
	GameSession.set_process(false)
	call_deferred("run")

func run() -> void:
	check(DirAccess.make_dir_recursive_absolute(temp_dir) == OK, "Temporary test directory exists")
	verify_definitions()
	verify_container_lifecycle()
	verify_quantity_and_permanent()
	verify_rejected_operations()
	verify_restore_and_files()
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
	print("SUPPLY INVENTORY: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size(), " (", checks, " checks)")
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if failures.is_empty() else 1)

func verify_definitions() -> void:
	var catalog := SupplyCatalogScript.new()
	var inventory := InventoryScript.new()
	check(catalog.last_error.is_empty(), "Supply definitions load")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/supplies/catalog.json"))
	var initial: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/supplies/initial_state.json"))
	check(catalog.list_items().size() == raw.items.size() and raw.items.size() == 32, "All 32 product definitions are available")
	check(initial.items.size() == raw.items.size(), "Initial player template contains every defined product")
	check(catalog.get_item(GIN).package.container_capacity == 750, "Gin capacity is 750 ml")
	for item: Dictionary in catalog.list_items():
		check(initial.items.has(item.id), "Initial state matches product ID: " + item.id)
		check(not item.id.begins_with("sku_ice_") and item.get("kind", "") != "ice", "Ice is excluded from product items: " + item.id)
		var state := inventory.get_state(item.id)
		if item.storage_mode == "permanent":
			check(state.get("unlocked", false) and state.get("owned", false) and inventory.total_remaining(item.id) == 1.0, "Tools and glasses are available from the start: " + item.id)
		else:
			check(not state.get("unlocked", true) and inventory.total_remaining(item.id) == 0.0, "New-game shop item begins locked and empty: " + item.id)
		if item.storage_mode == "permanent":
			check(state.get("owned", false) and not state.has("quantity") and not state.has("current_remaining"), "Permanent ownership matches defaults without consumable fields: " + item.id)
		elif item.storage_mode == "quantity":
			check(state.quantity == 0 and not state.has("current_remaining"), "Quantity item has no current-package remainder: " + item.id)
			check(item.package.purchase_quantity is int or item.package.purchase_quantity is float, "Quantity purchase size is numeric: " + item.id)
			check(item.package.purchase_quantity > 0 and item.package.purchase_quantity == floor(item.package.purchase_quantity), "Quantity purchase size is a positive whole count: " + item.id)
		else:
			check(state.quantity == 0 and state.current_remaining == 0, "Container starts with zero packages and remainder: " + item.id)
			check(is_finite(float(item.package.container_capacity)) and item.package.container_capacity > 0, "Container capacity is finite and positive: " + item.id)
	for category in raw.categories:
		for item: Dictionary in catalog.list_items(category):
			check(item.category == category, "Category filter does not mix products")
	check(catalog.list_ice().size() == 2, "Standard and crushed ice remain separate material definitions")
	for ice: Dictionary in catalog.list_ice():
		check(catalog.get_item(ice.id).is_empty(), "Ice cannot be purchased as a product: " + ice.id)
		check(not inventory.serialize().items.has(ice.id), "Ice has no player ingredient inventory entry: " + ice.id)
	var bridge := inventory.as_recipe_inventory()
	for cocktail: Dictionary in CocktailDatabase.list_cocktails():
		for ingredient: Dictionary in cocktail.ingredients:
			var item := catalog.get_item(ingredient.sku_id)
			check(not item.is_empty() and item.kind == "ingredient", "Recipe SKU has one matching ingredient product: " + ingredient.sku_id)
			check(bridge.has(ingredient.sku_id) and bridge[ingredient.sku_id] == 0, "Empty recipe stock is keyed by canonical SKU: " + ingredient.sku_id)
		for ice: Dictionary in cocktail.get("ice", []):
			check(not bridge.has(ice.sku_id), "Recipe ice never enters ingredient bridge: " + ice.sku_id)
	var product_copy := catalog.get_item(GIN)
	product_copy.package.container_capacity = 1
	check(catalog.get_item(GIN).package.container_capacity == 750, "Product getter returns a deep copy")
	var state_copy := inventory.get_state(GIN)
	state_copy.quantity = 10
	check(inventory.get_state(GIN).quantity == 0, "State getter returns a deep copy")

func verify_container_lifecycle() -> void:
	var inventory := InventoryScript.new()
	check(inventory.purchase(GIN, 2), "Two gin bottles can be purchased")
	var state := inventory.get_state(GIN)
	check(state.quantity == 2 and state.current_remaining == 750 and inventory.total_remaining(GIN) == 1500, "Purchase stores two bottles with one current full bottle")
	check(inventory.consume(GIN, 650), "First 650 ml can be consumed")
	state = inventory.get_state(GIN)
	check(state.quantity == 2 and state.current_remaining == 100 and inventory.total_remaining(GIN) == 850, "650 ml consumption leaves 100 ml in current bottle")
	check(inventory.consume(GIN, 100), "Current bottle's last 100 ml can be consumed")
	state = inventory.get_state(GIN)
	check(state.quantity == 1 and state.current_remaining == 750 and inventory.total_remaining(GIN) == 750, "Empty bottle is removed and next full bottle becomes current")
	check(inventory.consume(GIN, 750), "Last bottle can be exhausted")
	state = inventory.get_state(GIN)
	check(state.quantity == 0 and state.current_remaining == 0 and inventory.is_unlocked(GIN), "Exhaustion keeps ingredient permanently unlocked")
	check(inventory.purchase(GIN), "Exhausted ingredient can be restocked")
	check(inventory.get_state(GIN).current_remaining == 750 and inventory.get_state(GIN).quantity == 1, "Restock after exhaustion opens one full bottle")
	check(inventory.consume(GIN, 650) and inventory.purchase(GIN, 2), "Restock works while current bottle is partly used")
	state = inventory.get_state(GIN)
	check(state.quantity == 3 and state.current_remaining == 100 and inventory.total_remaining(GIN) == 1600, "Buying two bottles preserves opened bottle's 100 ml remainder")
	check(inventory.consume(GIN, 850), "One pour can cross current and unopened bottles")
	state = inventory.get_state(GIN)
	check(state.quantity == 1 and state.current_remaining == 750, "Cross-bottle exact boundary opens the next full bottle")
	check(inventory.consume(GIN, 22.5), "Fractional liquid amounts are supported")
	check(inventory.get_state(GIN).current_remaining == 727.5, "Fractional recipe amount preserves exact expected remainder")
	var bridge := inventory.as_recipe_inventory()
	check(bridge[GIN] == 727.5, "Recipe bridge reports total remaining volume")
	bridge[GIN] = 0
	check(inventory.total_remaining(GIN) == 727.5, "Recipe bridge does not alias stored state")
	var cross := InventoryScript.new()
	check(cross.purchase(GIN, 3) and cross.consume(GIN, 800), "Cross-bottle pour with a partial ending succeeds")
	state = cross.get_state(GIN)
	check(state.quantity == 2 and state.current_remaining == 700 and cross.total_remaining(GIN) == 1450, "800 ml from three bottles leaves two bottles, current 700 ml")

func verify_quantity_and_permanent() -> void:
	var inventory := InventoryScript.new()
	check(inventory.purchase(LIME, 2), "Two garnish packs can be purchased")
	var state := inventory.get_state(LIME)
	check(state.quantity == 40 and not state.has("current_remaining") and inventory.total_remaining(LIME) == 40, "Garnish packs contain 40 pieces with no package remainder")
	check(inventory.consume(LIME, 7) and inventory.get_state(LIME).quantity == 33, "Garnish consumption subtracts individual pieces")
	var before := inventory.serialize()
	check(not inventory.consume(LIME, 0.5) and same_state(inventory.serialize(), before), "Fractional garnish consumption is rejected without changing state")
	check(inventory.consume(LIME, 33) and inventory.is_unlocked(LIME), "Exhausted garnish remains unlocked")
	check(inventory.get_state(LIME).quantity == 0 and not inventory.get_state(LIME).has("current_remaining"), "Empty garnish still has only a quantity")
	for item: Dictionary in inventory.catalog.list_items():
		if item.storage_mode != "permanent":
			continue
		var id: String = item.id
		check(not inventory.purchase(id), "Default equipment cannot be purchased: " + id)
		state = inventory.get_state(id)
		check(state.owned and state.unlocked and inventory.total_remaining(id) == 1, "Permanent object stores owned state: " + id)
		before = inventory.serialize()
		check(not inventory.purchase(id, 2) and same_state(inventory.serialize(), before), "Default equipment purchase is rejected at any quantity: " + id)
		check(not inventory.consume(id, 1) and same_state(inventory.serialize(), before), "Permanent object cannot be consumed: " + id)
		check(not inventory.as_recipe_inventory().has(id), "Equipment or glass never enters ingredient stock bridge: " + id)
	before = inventory.serialize()
	check(not inventory.purchase("glass_highball_glass") and inventory.is_unlocked("glass_highball_glass") and same_state(inventory.serialize(), before), "Default serving glass cannot be purchased")

func verify_rejected_operations() -> void:
	var inventory := InventoryScript.new()
	check(inventory.purchase(GIN, 2), "Failure fixture owns two gin bottles")
	var before := inventory.serialize()
	for amount in [0.0, -1.0, NAN, INF, 1500.1]:
		check(not inventory.consume(GIN, amount), "Invalid or excessive pour is rejected: " + str(amount))
		check(same_state(inventory.serialize(), before), "Rejected pour changes no item state")
	for packages in [0, -1]:
		check(not inventory.purchase(GIN, packages) and same_state(inventory.serialize(), before), "Non-positive purchase quantity is rejected without changes")
	check(not inventory.purchase("missing") and same_state(inventory.serialize(), before), "Unknown product cannot be purchased")
	check(not inventory.consume("missing", 1) and same_state(inventory.serialize(), before), "Unknown product cannot be consumed")
	check(not inventory.consume(LIME, 1) and same_state(inventory.serialize(), before), "Empty ingredient cannot be consumed")
	for invalid in [null, [], {}, {"schema_version": 2, "items": {}}, {"schema_version": 1, "items": []}]:
		check(not inventory.restore(invalid) and same_state(inventory.serialize(), before), "Malformed save structure preserves all inventory")
	for patch in [{"quantity": -1}, {"quantity": 1.5}, {"quantity": 0, "current_remaining": 1}, {"current_remaining": 0}, {"current_remaining": 751}, {"unlocked": false}, {"unlocked": "yes"}, {"current_remaining": "100"}]:
		var invalid := before.duplicate(true)
		invalid.items[GIN].merge(patch, true)
		check(not inventory.restore(invalid) and same_state(inventory.serialize(), before), "Invalid bottle save preserves all inventory: " + str(patch))
	var invalid_late := before.duplicate(true)
	invalid_late.items["sku_cocktail_cherry"] = {"unlocked": true, "quantity": -1}
	check(not inventory.restore(invalid_late) and same_state(inventory.serialize(), before), "Late invalid quantity entry cannot partially commit earlier save entries")
	var copied := inventory.serialize()
	copied.items[GIN].quantity = 200
	check(same_state(inventory.serialize(), before), "Serialized save is a deep copy")

func verify_restore_and_files() -> void:
	var inventory := InventoryScript.new()
	check(inventory.purchase(GIN, 2) and inventory.consume(GIN, 650) and inventory.purchase(LIME) and inventory.consume(LIME, 4) and inventory.get_state(SHAKER).owned, "Save fixture contains opened stock, garnish pieces and default tool")
	var snapshot := inventory.serialize()
	var restored := InventoryScript.new()
	check(restored.restore(snapshot) and same_state(restored.serialize(), snapshot), "In-memory restore preserves exact inventory")
	var save_path := temp_dir.path_join("inventory.json")
	check(inventory.save_to(save_path), "Explicit inventory file can be saved")
	check(restored.load_from(save_path) and same_state(restored.serialize(), snapshot), "File reload preserves opened remainder, unlocks, counts and equipment")
	var file_before := FileAccess.get_file_as_string(save_path)
	check(not inventory.save_to(save_path.path_join("cannot-write.json")), "Save failure is reported")
	check(same_state(inventory.serialize(), snapshot) and FileAccess.get_file_as_string(save_path) == file_before, "Save failure changes neither inventory nor prior save file")
	check(inventory.save_to(save_path), "Saving can recover after a filesystem error")
	check(inventory.last_error.is_empty(), "Successful save clears the previous error")
	var invalid_path := temp_dir.path_join("invalid.json")
	write_json(invalid_path, {"schema_version": 1, "items": {GIN: {"unlocked": true, "quantity": 1, "current_remaining": 1000}}})
	var invalid_file := FileAccess.get_file_as_string(invalid_path)
	check(not restored.load_from(invalid_path) and same_state(restored.serialize(), snapshot), "Invalid file contents do not alter previous state")
	check(FileAccess.get_file_as_string(invalid_path) == invalid_file, "Invalid source save is not overwritten")
	check(not restored.load_from(temp_dir.path_join("missing.json")) and same_state(restored.serialize(), snapshot), "Missing save does not alter previous state")
	var older_save := snapshot.duplicate(true)
	older_save.items.erase(GIN)
	older_save.items.erase(SHAKER)
	older_save.items.erase("sku_mint_leaf")
	older_save.items["future_unknown_item"] = {"unlocked": true, "quantity": 10}
	check(restored.purchase("sku_mint_leaf") and restored.restore(older_save), "Older partial save restores after object already held newer stock")
	check(restored.get_state(GIN) == {"unlocked": false, "quantity": 0, "current_remaining": 0.0}, "New container absent from older save starts locked and empty")
	check(restored.get_state(SHAKER) == {"unlocked": true, "owned": true}, "Equipment absent from older save becomes default owned")
	check(restored.get_state("sku_mint_leaf") == {"unlocked": false, "quantity": 0}, "New quantity item absent from older save starts locked and empty")
	check(restored.get_state("future_unknown_item").is_empty(), "Unknown legacy item is not admitted into inventory")
	check(restored.get_state(LIME).quantity == 16 and restored.get_state(LIME).unlocked, "Existing older-save item keeps quantity and unlock")
	older_save.items.erase("glass_highball_glass")
	older_save.items["glass_saucer_glass"] = {"owned": false, "unlocked": false}
	older_save.items["tool_mixing_glass"] = {"owned": false, "unlocked": false}
	check(restored.restore(older_save) and restored.get_state("glass_highball_glass").owned and restored.get_state("glass_saucer_glass").owned and restored.get_state("tool_mixing_glass").owned, "Older missing or locked glasses and tools upgrade to default ownership")
	restored.reset()
	var initial: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/supplies/initial_state.json"))
	check(same_state(restored.serialize(), initial), "Explicit reset returns to all declared new-game initial values")
