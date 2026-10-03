extends "res://tests/verify_workbench_evaluation.gd"

func run() -> void:
	definitions=WorkbenchSession.MATERIALS.duplicate(true)
	definitions.merge(WorkbenchSession.SOLIDS)
	definitions.merge(WorkbenchSession.GARNISHES)
	var recipe: Dictionary=MenuCatalog.get_recipe("gin_and_tonic")
	check(recipe.glass=="高球杯" and not JSON.stringify(recipe).contains("球形杯"),"catalog and notes consistently specify highball")
	for id in Eval.config().rules:
		var official: Dictionary=MenuCatalog.get_recipe(id)
		if official.is_empty(): continue
		check(Eval.config().rules[id].get("cup","")==WorkbenchSession.recommended_cup(official),"evaluation agrees with catalogue cup: "+id)
	check(Supplies.purchase("sku_tonic_water"),"buy tonic in isolated test profile")
	check(MenuCatalog.save_menu([{"id":"gin_and_tonic","price":35}],MenuCatalog.design),"list Gin & Tonic")
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	check(bench._issue("select_recipe",{"recipe_id":"gin_and_tonic"}) and bench.data.cup=="highball","selection creates a highball")
	for i in range(3): check(bench._issue("ice",{"vessel":"glass","ice":"cube"}),"serving ice")
	check(bench._issue("withdraw",{"material":"gin","ml":50,"vessel":"glass"}),"50 ml gin")
	check(bench._issue("withdraw",{"material":"sku_tonic_water","ml":150,"vessel":"glass"}),"150 ml tonic")
	check(bench._issue("spoon",{"target":"glass"}),"insert spoon")
	for i in range(8): check(bench._issue("stir",{"vessel":"glass","seconds":.5,"control":1}),"gentle stir")
	check(bench._issue("garnish",{"material":"garnish"}),"lime garnish")
	check(bench._issue("finish"),"finish Gin & Tonic")
	var result: Dictionary=bench.data.result.evaluation
	check(result.subscores.finish==100 and result.score==100 and result.tier=="perfect","correct highball Gin & Tonic gets full finish score")
	check(not JSON.stringify(result.reasons).contains("推荐杯型不同"),"highball has no cup mismatch warning")
	var balloon: Dictionary=bench.data.duplicate(true)
	balloon.cup="glass_balloon_glass"
	check(JSON.stringify(Eval.evaluate(balloon,definitions).reasons).contains("推荐杯型不同"),"obsolete balloon cup no longer counts as recommended")
	bench._result()
	await capture("51-gin-tonic-highball-perfect")
	cancel()
	# Emulate the old cached result, then reload it through the real persistence path.
	var legacy: Dictionary=WorkbenchSession.snapshot()
	legacy.session.result.evaluation.version="quality-playtest-2"
	legacy.session.result.evaluation.reasons.append("使用的杯型与这款酒的推荐杯型不同。")
	legacy.session.result.evaluation.subscores.finish=66.6667
	legacy.history.append(legacy.session.duplicate(true))
	check(WorkbenchSession._commit(legacy),"persist old evaluation fixture")
	var supplies_before: Dictionary=Supplies.inventory.serialize().duplicate(true)
	var gold: int=SlotWallet.balance
	check(Supplies.load_state() and WorkbenchSession.load_state(),"reload repairs current and historical Gin & Tonic evaluations")
	var repaired: Dictionary=WorkbenchSession.snapshot()
	check(repaired.session.result.evaluation.subscores.finish==100 and repaired.history.back().result.evaluation.subscores.finish==100,"both cached results are repaired")
	var unchanged: Dictionary=repaired.session.duplicate(true)
	unchanged.result.evaluation=legacy.session.result.evaluation
	check(same(unchanged,legacy.session) and same(supplies_before,Supplies.inventory.serialize()) and gold==SlotWallet.balance,"repair does not change actual cup actions contents stock or gold")
	check(not WorkbenchSession._repair_gin_tonic_evaluations(repaired),"repaired version does not trigger a second migration")
	check(Supplies.load_state() and WorkbenchSession.load_state() and same(WorkbenchSession.state,repaired),"corrected judgement persists on disk")
	print("GIN TONIC CUP: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
