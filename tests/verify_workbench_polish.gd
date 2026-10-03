extends "res://tests/verify_workbench_drag.gd"
const Eval=preload("res://scripts/workbench_evaluation.gd")

func _ready() -> void:
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	super._ready()

func run() -> void:
	var helper=load("res://tests/verify_workbench_evaluation.gd").new()
	var definitions: Dictionary=WorkbenchSession.MATERIALS.duplicate(true)
	definitions.merge(WorkbenchSession.SOLIDS)
	definitions.merge(WorkbenchSession.GARNISHES)
	for mask in range(8):
		var quantities: Dictionary={}
		for i in range(3): quantities[["gin","lime","syrup"][i]]=[30,20,10][i]*(.9 if mask&(1<<i) else 1.1)
		var quality:=Eval.evaluate(helper.sample(quantities),definitions)
		check(quality.score>=80 and quality.tier=="excellent","recommended-dose boundary stays good without auto-perfect %d" % mask)
	var reference: Dictionary=helper.sample({"gin":30,"lime":20,"syrup":10})
	for duration in [6,8,10]:
		var s:=reference.duplicate(true)
		s.actions[4].payload.seconds=duration
		check(Eval.evaluate(s,definitions).tier=="perfect","best duration is an interval: %s" % duration)
	var short:=reference.duplicate(true)
	short.actions[4].payload.seconds=1
	check(Eval.evaluate(short,definitions).tier!="perfect","brief gesture cannot complete full mixing")
	var rough:=reference.duplicate(true)
	rough.actions[4].payload.control=.55
	check(Eval.evaluate(rough,definitions).tier!="perfect","rushed control affects process quality")
	helper.free()
	WorkbenchSession.reset_game()
	SlotWallet.balance=300000
	SlotWallet.persist()
	for id in ["sku_mint_leaf","sku_mint_sprig","sku_white_cane_sugar"]: Supplies.purchase(id)
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	var stock:=WorkbenchSession.remaining("gin")
	for quantity in [27.2,32.4]:
		bench._begin_measure("gin",30,"jigger")
		bench.measure.set_process(false)
		bench.measure.progress=quantity/bench.measure.volume_limit()
		bench.measure_waiting=false
		await capture("54-red-target-real-dose")
		space()
		check(is_equal_approx(bench.data.vessels.jigger.contents.gin,quantity) and bench.data.actions.back().payload.golden,"golden region preserves actual dose %s" % quantity)
		bench._act("transfer",{"source":"jigger","vessel":"shaker"})
		await get_tree().create_timer(1.2).timeout
	check(is_equal_approx(WorkbenchSession.remaining("gin"),stock-59.6),"decimal doses consume their exact total once")
	await get_tree().create_timer(1.2).timeout
	await capture("55-shaker-no-color-ring")
	bench._act("lid")
	bench._select("shaker")
	for i in range(16): bench._issue("shake",{"vessel":"shaker","seconds":.5,"control":1})
	await settle()
	check(bench.technique_panel.visible and bench.technique_title.text.contains("已到位"),"live technique card indicates recommended window")
	await capture("56-ready-to-stop")
	DisplayServer.window_set_size(Vector2i(960,540))
	await settle()
	await capture("60-guidance-small-window")
	DisplayServer.window_set_size(Vector2i(1280,720))
	await settle()
	var paused_progress: float=bench.guidance_trace.min_seconds
	await get_tree().create_timer(.3).timeout
	check(bench.guidance_trace.min_seconds==paused_progress,"idle time does not advance material mixing")
	var saved: Dictionary=WorkbenchSession.snapshot()
	check(not bench._issue("shake",{"vessel":"shaker","seconds":.5,"control":1.5}) and WorkbenchSession.state==saved,"invalid control cannot change session or quality")
	check(Supplies.load_state() and WorkbenchSession.load_state(),"duration and control metadata restore")
	bench._refresh()
	check(is_equal_approx(bench.guidance_trace.min_seconds,8),"loaded cup keeps its processing progress")
	bench._act("lid")
	bench._issue("withdraw",{"material":"lime","ml":10,"vessel":"shaker"})
	check(bench.guidance_trace.min_seconds==0,"new liquid resets only its own mixing progress")
	MenuCatalog.unlocked_ids.assign(["mojito"])
	MenuCatalog.save_menu([{"id":"mojito","price":45}],MenuCatalog.design)
	check(bench._issue("select_recipe",{"recipe_id":"mojito","replace_session_id":bench.data.id}),"fresh Mojito uses its matching stir guidance")
	for id in ["rum","syrup","lime","soda"]:
		bench._issue("withdraw",{"material":id,"ml":{"rum":45,"syrup":15,"lime":20,"soda":60}[id],"vessel":"glass"})
	bench._act("ice",{"vessel":"glass","ice":"crushed"})
	for i in range(6): bench._act("add_solid",{"material":"sku_mint_leaf","vessel":"glass"})
	for id in ["garnish","lemon_slice","sku_mint_sprig"]: bench._act("garnish",{"material":id})
	bench._show_category("装饰")
	bench._select("glass")
	await get_tree().create_timer(1.5).timeout
	await capture("57-larger-mint-ice-garnishes")
	bench._act("spoon",{"target":"glass"})
	bench._set_technique("stir")
	bench._issue("muddle",{"vessel":"glass","seconds":.25})
	for i in range(10): bench._issue("stir",{"vessel":"glass","seconds":.5,"control":1})
	await settle()
	check(bench.technique_title.text.contains("搅拌") and bench.technique_title.text.contains("已到位"),"stir guidance displays its own timing window")
	await capture("58-stir-guidance")
	bench._finish()
	await settle()
	await capture("59-polished-finished-cup")
	print("WORKBENCH POLISH: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
