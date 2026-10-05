extends Node
const Sensory := preload("res://scripts/sensory_model.gd")
const Research := preload("res://scripts/research_data.gd")
const Craft := preload("res://scripts/workbench_evaluation.gd")
const Customer := preload("res://scripts/customer_evaluation.gd")
var checks := 0
var failures: Array = []
var rows: Array = []
var serial := 0
var definitions: Dictionary = {}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label + " | " + WorkbenchSession.last_error + " / " + CustomerService.last_error)

func equal_attributes(left: Dictionary, right: Dictionary, label: String) -> void:
	for field in Sensory.ATTRS:
		check(left.has(field) and right.has(field) and absf(float(left.get(field, -999)) - float(right.get(field, -999))) < 0.00001, label + " " + field)

func command(kind: String, payload: Dictionary = {}) -> bool:
	serial += 1
	var okay: bool = WorkbenchSession.command("sensory-test-%d" % serial, str(WorkbenchSession.state.session.get("id", "")), kind, payload)
	check(okay, kind)
	return okay

func brew(id: String) -> Dictionary:
	var quote := CustomerService.prepare_order(id)
	check(not quote.is_empty(), "order locks " + id)
	command("select_recipe", {"recipe_id":id, "guest":{"id":"stick", "visit_id":quote.get("visit_id", "")}})
	var session: Dictionary = WorkbenchSession.state.session
	check(session.sensory_model == CustomerService.state.active.rules_snapshot.sensory, "order and bench freeze identical model " + id)
	var rule: Dictionary = session.quality_model.rules[id]
	var vessel := "shaker" if rule.mix == "shake" else "mixing" if rule.get("filter", false) else "glass"
	for row: Dictionary in session.recipe.ingredient_rows:
		if row.use != "装饰" and row.inventory_unit == "piece":
			var alias: String = WorkbenchSession.ITEM_ALIASES.get(row.sku_id, row.sku_id)
			for i in range(int(row.inventory_amount)): command("add_solid", {"material":alias, "vessel":vessel})
	if rule.has("muddle"):
		for i in range(2): command("muddle", {"vessel":vessel, "seconds":0.5})
	for i in range(3): command("ice", {"vessel":vessel, "ice":rule.get("serving_ice", "cube")})
	for material: String in session.recipe.ingredients:
		command("withdraw", {"material":material, "vessel":vessel, "ml":session.recipe.ingredients[material]})
	if rule.mix == "shake": command("lid")
	else: command("spoon", {"target":vessel})
	var seconds := (float(rule.time_window[0]) + float(rule.time_window[1])) / 2.0
	for i in range(int(seconds / 0.5)): command(rule.mix, {"vessel":vessel, "seconds":0.5, "control":1.0})
	if rule.get("filter", false): command("filter", {"source":vessel, "vessel":"glass", "integrated_strainer":vessel == "shaker"})
	for sku in rule.get("garnishes", {}):
		var material: String = WorkbenchSession.ITEM_ALIASES.get(sku, sku)
		for i in range(int(rule.garnishes[sku])): command("garnish", {"material":material, "vessel":"glass"})
	command("finish")
	return WorkbenchSession.state.session.result.duplicate(true)

func verify_cup(id: String, number: int) -> void:
	StoryDialogue.start_guest("stick")
	check(CustomerService.begin_guest({"id":"stick", "name":"小线"}, number, false), "begin " + id)
	var cup := brew(id)
	check(cup.evaluation.score == 100 and cup.evaluation.tier == "perfect", "standard quality perfect " + id)
	var source := CocktailDatabase.get_cocktail(id)
	var standard := Sensory.standard(source)
	check(standard.data_complete, "complete standard " + id)
	equal_attributes(source, standard.attributes, "catalog " + id)
	equal_attributes(cup.evaluation.attributes, standard.attributes, "bench " + id)
	var trial: Dictionary = WorkbenchSession.state.session.duplicate(true)
	trial.mode = "research_diy"
	var diy := Research.trial(trial, definitions)
	equal_attributes(diy.attributes, standard.attributes, "DIY " + id)
	var changed_recipe := trial.duplicate(true)
	changed_recipe.recipe = {"id":"research_blank", "version":1, "name":"随意改名", "ingredients":{}}
	equal_attributes(Research.trial(changed_recipe, definitions).attributes, diy.attributes, "DIY name independent " + id)
	var wrong_label: Dictionary = WorkbenchSession.state.session.duplicate(true)
	wrong_label.recipe.alcohol_intensity = 1
	wrong_label.recipe.sourness = 99
	equal_attributes(Craft.evaluate(wrong_label, definitions).attributes, cup.evaluation.attributes, "actual ignores target edits " + id)
	var before: int = SlotWallet.balance
	check(CustomerService.deliver(cup), "settle " + id)
	var record := CustomerService.current_record()
	check(not record.is_empty(), "receipt exists " + id)
	if record.is_empty(): return
	equal_attributes(record.actual.attributes, standard.attributes, "customer " + id)
	check(SlotWallet.balance == before + 80, "locked payment " + id)
	check(CustomerService.deliver(cup) and SlotWallet.balance == before + 80, "idempotent payment " + id)
	check(CustomerService._valid_saved_state(CustomerService.state), "save validates " + id)
	check(WorkbenchSession._valid(WorkbenchSession.state), "workbench save validates " + id)
	rows.append({"id":id, "name":source.name, "catalog":standard.attributes, "bench":cup.evaluation.attributes, "diy":diy.attributes, "customer":record.actual.attributes, "craft":cup.evaluation.score, "total":record.review.satisfaction})
	check(CustomerService.end_guest(), "end " + id)
	StoryDialogue.end_guest()

func pure_cases() -> void:
	var model := Sensory.snapshot()
	check(Sensory.valid_model(model), "shared config valid")
	var last := Sensory.standard(CocktailDatabase.get_cocktail("last_word"), model)
	check(last.attributes.sourness == 65 and last.attributes.alcohol_intensity == 65, "Last Word does not saturate")
	var watered: Dictionary = last.contents.duplicate(true)
	watered.sku_soda_water = 90.0
	var light := Sensory.evaluate(watered, last.solids, {}, model)
	check(light.data_complete, "dilution data complete")
	for field in Sensory.ATTRS: check(light.attributes[field] < last.attributes[field], "dilution monotonic " + field)
	var lime: Dictionary = last.contents.duplicate(true)
	lime.sku_lime_juice += 10
	check(Sensory.evaluate(lime, {}, {}, model).attributes.sourness > last.attributes.sourness, "more lime increases acidity")
	var sugar: Dictionary = last.contents.duplicate(true)
	sugar.sku_simple_syrup = 15
	var sweeter := Sensory.evaluate(sugar, {}, {}, model)
	check(sweeter.data_complete and sweeter.attributes.sweetness > last.attributes.sweetness, "more syrup increases sweetness")
	var customer_named := Customer.sensory({"contents":{"contents":sugar, "solids":{}, "garnishes":[]}}, {}, CustomerService.rules)
	check(customer_named.status == "complete", "customer StringName material keys")
	equal_attributes(customer_named.attributes, sweeter.attributes, "customer native keys")
	var doubled: Dictionary = {}
	for id in last.contents: doubled[id] = 2 * float(last.contents[id])
	equal_attributes(Sensory.evaluate(doubled, {}, {}, model).attributes, last.attributes, "same ratio")
	var aliases := Sensory.evaluate({"gin":25, "sku_gin_london_dry":25, "sku_tonic_water":150}, {}, definitions, model)
	equal_attributes(aliases.attributes, CocktailDatabase.get_cocktail("gin_and_tonic"), "duplicate alias sums")
	check(not Sensory.evaluate({"unknown":10}, {}, {}, model).data_complete, "unknown ingredient fails")
	check(not Sensory.evaluate({"gin":-1}, {}, {}, model).data_complete, "negative fails")
	check(not Sensory.evaluate({}, {}, {}, model).data_complete, "empty fails")
	check(not Sensory.evaluate({"gin":NAN}, {}, {}, model).data_complete, "NaN fails")
	check(not Sensory.evaluate({"gin":1.0e308}, {}, {}, model).data_complete, "overflow fails")
	var old := WorkbenchSession._session(999)
	old.erase("sensory_model")
	old.vessels.glass.contents = old.recipe.ingredients.duplicate(true)
	var legacy := Craft.evaluate(old, definitions)
	check(Craft.valid(legacy) and legacy.sensory_model_version == "legacy-quality", "legacy branch still readable")
	var legacy_model := {"version":"research-sensory-1", "profiles":Craft.config().profiles.duplicate(true)}
	old.sensory_model = legacy_model
	check(Research.valid_model(legacy_model), "legacy DIY model validates")
	var legacy_diy := Research.attributes(old, definitions)
	check(legacy_diy.version == "research-sensory-1", "legacy DIY stays legacy")

func _ready() -> void:
	await get_tree().process_frame
	if not str(Supplies.save_path).begins_with("/tmp/") and not str(Supplies.save_path).begins_with("/private/tmp/"):
		get_tree().quit(2)
		return
	if "--resume-check" in OS.get_cmdline_user_args():
		check(CustomerService.writable and WorkbenchSession.writable and Supplies.writable, "services restore after new process")
		check(CustomerService.state.deliveries.size() == 5, "all five records restore")
		check(WorkbenchSession.state.session.status == "finished", "finished cup restores")
		var restored: Dictionary = WorkbenchSession.state.session.result
		check(restored.get("sensory_model", {}).get("version") == Sensory.VERSION, "finished model restores")
		for receipt: Dictionary in CustomerService.state.deliveries.values():
			check(receipt.rules_snapshot.sensory.version == Sensory.VERSION, "frozen customer model restores")
			var expected := Sensory.standard(CocktailDatabase.get_cocktail(receipt.recipe_id), receipt.rules_snapshot.sensory)
			equal_attributes(receipt.actual.attributes, expected.attributes, "restored receipt " + str(receipt.recipe_id))
		print(JSON.stringify({"suite":"unified_model_process_restore", "checks":checks, "passed":failures.is_empty(), "failures":failures}))
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	CustomerService.endpoint = ""
	TimeManager.restore({"day":1, "minutes":1200})
	TimeManager.set_running(false)
	SlotWallet.balance = 2000000
	check(SlotWallet.persist(), "private wallet saved")
	definitions = WorkbenchSession.MATERIALS.duplicate(true)
	definitions.merge(WorkbenchSession.SOLIDS)
	definitions.merge(WorkbenchSession.GARNISHES)
	var purchased: Dictionary = {}
	MenuCatalog.entries = []
	for record: Dictionary in CocktailDatabase.list_cocktails():
		MenuCatalog.entries.append({"id":record.id,"price":80})
		for row: Dictionary in record.ingredients:
			if not purchased.has(row.sku_id):
				check(Supplies.purchase(row.sku_id, 3), "buy " + row.sku_id)
				purchased[row.sku_id] = true
	var number := 0
	for id in ["last_word","mojito","gin_and_tonic","long_island_iced_tea","manhattan"]:
		number += 1
		await verify_cup(id, number)
	pure_cases()
	var summary := {"suite":"shared_sensory_actual_five_cup_flow", "checks":checks,"passed":failures.is_empty(), "failures":failures,"rows":rows}
	print(JSON.stringify(summary))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			var file := FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE)
			file.store_string(JSON.stringify(summary, "  "))
			file.close()
	get_tree().quit(0 if failures.is_empty() else 1)
