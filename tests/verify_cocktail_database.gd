extends Node

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	TimeManager.set_process(false)
	call_deferred("run")

func run() -> void:
	check(CocktailDatabase.last_error.is_empty(), "Cocktail catalogue loaded")
	check(CocktailDatabase.list_cocktails().size() == 5, "Five classic cocktails imported")
	check(CocktailDatabase.list_cocktails("特调").is_empty(), "Unconfirmed special recipe is excluded")
	var expected := {
		"last_word": [65, 45, 65, 20],
		"mojito": [40, 35, 45, 0],
		"gin_and_tonic": [35, 25, 20, 30],
		"long_island_iced_tea": [55, 55, 45, 10],
		"manhattan": [75, 30, 10, 35],
	}
	var ingredient_count := 0
	var ice_count := 0
	var codex_positions: Array = []
	for id: String in expected:
		var cocktail := CocktailDatabase.get_cocktail(id)
		check(not cocktail.is_empty(), "Stable source ID: " + id)
		if cocktail.is_empty():
			continue
		check(cocktail.type == "经典", "Classic type retained: " + id)
		for field_index in range(CocktailDatabase.SCORE_FIELDS.size()):
			var field: String = CocktailDatabase.SCORE_FIELDS[field_index]
			check(float(cocktail[field]) == float(expected[id][field_index]), "Exact source score: " + id + " " + field)
		check(not cocktail.mouthfeel_tags.is_empty(), "Mouthfeel tags retained: " + id)
		ingredient_count += cocktail.ingredients.size()
		ice_count += cocktail.get("ice", []).size()
		codex_positions.append(int(cocktail.get("codex_order", -1)))
		check(not str(cocktail.get("story", "")).is_empty(), "Story available: " + id)
		check(not str(cocktail.get("preparation", "")).is_empty(), "Preparation overview available: " + id)
		check(not cocktail.get("display_equipment", []).is_empty(), "Required tools available: " + id)
		check(cocktail.get("display_steps", []).size() == cocktail.steps.size(), "Readable steps preserve source sequence: " + id)
		for ingredient in cocktail.ingredients:
			check(ingredient.use not in ["制作冰", "出品冰"], "Ice is excluded from ingredients: " + id)
		var texture := CocktailDatabase.get_image(id)
		check(texture != null and texture.get_width() > 0 and texture.get_height() > 0, "Imported finished-drink image: " + id)
	check(ingredient_count == 27, "27 ingredients retained; ice is not an ingredient")
	check(ice_count == 5, "All five ice records retained separately")
	codex_positions.sort()
	check(codex_positions == [2, 3, 4, 5, 6], "First codex position is reserved for the tutorial drink")
	var mojito := CocktailDatabase.get_cocktail("mojito")
	for ingredient in mojito.get("ingredients", []):
		if ingredient.sku_id == "sku_mint_leaf":
			check(ingredient.amount == 6 and ingredient.unit == "piece", "Six mint leaves retained")
	for ice in mojito.get("ice", []):
		if ice.sku_id == "sku_ice_crushed":
			check(ice.amount == 150 and ice.unit == "g", "Mojito uses crushed ice")
			check(ice.inventory_policy == "excluded_from_ingredient_inventory", "Ice never enters ingredient ownership or unlock checks")
	var long_island := CocktailDatabase.get_cocktail("long_island_iced_tea")
	for ingredient in long_island.get("ingredients", []):
		if ingredient.sku_id == "sku_lemon_slice":
			check(not ingredient.required, "Optional lemon slice remains optional")
	var manhattan := CocktailDatabase.get_cocktail("manhattan")
	for ingredient in manhattan.get("ingredients", []):
		if ingredient.sku_id == "sku_angostura_bitters":
			check(ingredient.amount == 1 and ingredient.unit == "dash" and ingredient.conversion_factor == null and ingredient.inventory_amount == null, "Unknown dash conversion remains null")
	mojito.sweetness = 999
	mojito.ingredients.clear()
	check(CocktailDatabase.get_cocktail("mojito").sweetness == 35 and not CocktailDatabase.get_cocktail("mojito").ingredients.is_empty(), "Readers cannot modify catalogue definitions")
	check(CocktailDatabase.get_cocktail("missing").is_empty() and CocktailDatabase.get_image("missing") == null, "Unknown IDs return empty results")
	print("COCKTAIL DATABASE: ", "PASS" if failures.is_empty() else failures)
	SaloonAudio.set_process(false)
	if is_instance_valid(SaloonAudio.fade):
		SaloonAudio.fade.kill()
	for player in SaloonAudio.players:
		player.stop()
		player.stream = null
	SaloonAudio._streams.clear()
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0 if failures.is_empty() else 1)
