extends "res://tests/verify_workbench_drag.gd"
const Eval=preload("res://scripts/workbench_evaluation.gd")
var definitions: Dictionary={}

func _ready() -> void:
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	super._ready()

func action(kind: String, payload: Dictionary) -> Dictionary:
	return {"kind":kind,"payload":payload}

func sample(amounts: Dictionary, mixed:=true, filtered:=true) -> Dictionary:
	var session: Dictionary=WorkbenchSession._session(1)
	for id in amounts:
		session.actions.append(action("withdraw",{"material":id,"ml":amounts[id],"vessel":"shaker"}))
	session.actions.append(action("ice",{"vessel":"shaker","ice":"cube"}))
	if mixed: session.actions.append(action("shake",{"vessel":"shaker","seconds":8.0}))
	session.actions.append(action("filter" if filtered else "transfer",{"source":"shaker","vessel":"glass"}))
	session.vessels.glass.contents=amounts.duplicate(true)
	return session

func same(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a))==JSON.parse_string(JSON.stringify(b))

func has_tag(e: Dictionary, text: String) -> bool:
	for tag in e.tags:
		if tag.text==text: return true
	return false

func make_drink(amounts: Dictionary, mix:=true) -> void:
	if not bench.data.is_empty() and bench.data.status=="mixing": bench._issue("discard")
	bench._issue("start")
	bench._act("cup",{"cup":"coupe"})
	for id in amounts: bench._issue("withdraw",{"material":id,"ml":amounts[id],"vessel":"shaker"})
	bench._act("ice",{"vessel":"shaker","ice":"cube"})
	bench._act("lid")
	if mix:
		for i in range(16): bench._issue("shake",{"vessel":"shaker","seconds":.5,"control":1})
	bench._act("filter",{"source":"shaker","vessel":"glass","integrated_strainer":true})
	bench._finish()
	await settle()

func run() -> void:
	definitions=WorkbenchSession.MATERIALS.duplicate(true)
	definitions.merge(WorkbenchSession.SOLIDS)
	definitions.merge(WorkbenchSession.GARNISHES)
	var standard:=sample({"gin":30,"lime":20,"syrup":10})
	var perfect:=Eval.evaluate(standard,definitions)
	check(perfect.tier=="perfect" and perfect.score==100,"exact recipe and required process yield perfect quality")
	check(perfect.attributes==perfect.targets,"reference composition anchors target attributes")
	var reordered:=sample({"syrup":10,"gin":30,"lime":20})
	check(Eval.evaluate(reordered,definitions).score==perfect.score,"ingredient arrival order within a mixed batch does not penalize")
	var doubled:=Eval.evaluate(sample({"gin":60,"lime":40,"syrup":20}),definitions)
	check(doubled.attributes==perfect.attributes and doubled.subscores.recipe<100,"double quantity changes portion score but not taste ratios")
	var sweet:=Eval.evaluate(sample({"gin":30,"lime":20,"syrup":60}),definitions)
	check(sweet.attributes.sweetness>perfect.attributes.sweetness and has_tag(sweet,"齁甜的"),"excess syrup produces higher sweetness and cloying tag")
	var acid:=Eval.evaluate(sample({"gin":30,"lime":70,"syrup":10}),definitions)
	check(acid.attributes.sourness>perfect.attributes.sourness and has_tag(acid,"尖酸的") and not has_tag(acid,"酸涩的"),"acid rises without inventing astringency")
	var thin:=Eval.evaluate(sample({"gin":30,"lime":20,"syrup":10,"soda":120}),definitions)
	check(thin.attributes.alcohol_intensity<perfect.attributes.alcohol_intensity and has_tag(thin,"寡淡的"),"extra water-like mixer reduces sensory concentration")
	var missing:=Eval.evaluate(sample({"syrup":80},false),definitions)
	check(missing.tier=="terrible","missing principal ingredients and technique yields terrible quality")
	var no_mix:=Eval.evaluate(sample({"gin":30,"lime":20,"syrup":10},false),definitions)
	check(no_mix.score<60 and has_tag(no_mix,"融合不足") and no_mix.attributes==perfect.attributes,"missing mixing affects process but cannot invent different whole-cup ingredient ratios")
	var late:=standard.duplicate(true)
	late.actions.remove_at(2)
	late.actions.insert(4,action("withdraw",{"material":"syrup","ml":10,"vessel":"shaker"}))
	var late_result:=Eval.evaluate(late,definitions)
	check(is_equal_approx(late_result.trace.mixed,50) and late_result.score<100,"ingredient added after shake does not inherit earlier processing")
	var irrelevant:=standard.duplicate(true)
	irrelevant.actions.insert(0,action("withdraw",{"material":"soda","ml":90,"vessel":"mixing"}))
	irrelevant.actions.insert(1,action("stir",{"vessel":"mixing","seconds":.5}))
	check(Eval.evaluate(irrelevant,definitions).attributes==perfect.attributes and Eval.evaluate(irrelevant,definitions).score==100,"wasted material and unrelated actions never alter served drink")
	var empty_shake:=sample({"gin":30,"lime":20,"syrup":10},false)
	empty_shake.actions.insert(0,action("shake",{"vessel":"shaker","seconds":.5}))
	check(Eval.evaluate(empty_shake,definitions).trace.mixed==0,"empty-container gestures cannot pre-credit future ingredients")
	var decorated:=standard.duplicate(true)
	decorated.vessels.glass.garnish=true
	decorated.vessels.glass.garnishes=["lemon_slice","garnish","lemon_slice"]
	check(Eval.evaluate(decorated,definitions).attributes==perfect.attributes,"rim citrus is not silently converted to juice")
	var sugar:=standard.duplicate(true)
	sugar.vessels.glass.solids={"sku_white_cane_sugar":20}
	var sugar_result:=Eval.evaluate(sugar,definitions)
	check(sugar_result.attributes.sweetness>perfect.attributes.sweetness and sugar_result.tier!="perfect","extra solid sugar affects both flavour and recipe adherence")
	var not_filtered:=Eval.evaluate(sample({"gin":30,"lime":20,"syrup":10},true,false),definitions)
	check(not_filtered.tier!="perfect" and not_filtered.subscores.finish<100,"missing filter is a real finish defect")
	var no_ice:=standard.duplicate(true)
	no_ice.actions.remove_at(3)
	check(Eval.evaluate(no_ice,definitions).subscores.process<100,"ice must be present during required processing")
	var diy:=standard.duplicate(true)
	diy.recipe.source_kind="diy"
	diy.vessels.glass.contents={"syrup":80}
	var trial:=Eval.evaluate(diy,definitions)
	check(trial.tier=="trial" and trial.score==null,"DIY deviation has no bad classic quality grade")
	var last_word:=sample({"gin":22.5,"lime":22.5,"sku_green_chartreuse":22.5,"sku_maraschino":22.5})
	last_word.recipe=WorkbenchSession.recipe_snapshot(MenuCatalog.get_recipe("last_word"))
	last_word.cup="glass_cocktail_glass"
	var last_eval:=Eval.evaluate(last_word,definitions)
	check(last_eval.tier=="perfect" and is_equal_approx(last_eval.attributes.alcohol_intensity,63.25) and is_equal_approx(last_eval.attributes.sourness,26.0) and last_word.recipe.design_attributes.alcohol_intensity==65,"Last Word uses common sensory model and preserves original design targets")
	var mojito: Dictionary=WorkbenchSession._session(2)
	mojito.recipe=WorkbenchSession.recipe_snapshot(MenuCatalog.get_recipe("mojito"))
	mojito.cup="highball"
	mojito.vessels.glass.contents={"rum":45,"syrup":15,"lime":20,"soda":60}
	mojito.vessels.glass.solids={"sku_mint_leaf":6}
	mojito.vessels.glass.ice="crushed"
	mojito.vessels.glass.ice_batches=[{"kind":"crushed","volume":40}]
	mojito.vessels.glass.garnish=true
	mojito.vessels.glass.garnishes=["sku_mint_sprig","garnish"]
	for id in ["syrup","lime"]: mojito.actions.append(action("withdraw",{"material":id,"ml":mojito.vessels.glass.contents[id],"vessel":"glass"}))
	for i in range(6): mojito.actions.append(action("add_solid",{"material":"sku_mint_leaf","vessel":"glass"}))
	mojito.actions.append(action("muddle",{"vessel":"glass","seconds":.25}))
	mojito.actions.append(action("ice",{"vessel":"glass","ice":"crushed"}))
	for id in ["rum","soda"]: mojito.actions.append(action("withdraw",{"material":id,"ml":mojito.vessels.glass.contents[id],"vessel":"glass"}))
	mojito.actions.append(action("stir",{"vessel":"glass","seconds":4.0}))
	var mojito_eval:=Eval.evaluate(mojito,definitions)
	check(mojito_eval.tier=="perfect" and is_equal_approx(mojito_eval.attributes.sweetness,12.5714285714) and is_equal_approx(mojito_eval.attributes.bitterness,1.2142857143) and mojito.recipe.design_attributes.sweetness==35,"Mojito preserves process requirements and original target while showing common sensory values")
	var shaken_soda:=mojito.duplicate(true)
	shaken_soda.actions.append(action("transfer",{"source":"glass","vessel":"shaker"}))
	shaken_soda.actions.append(action("shake",{"vessel":"shaker","seconds":.25}))
	shaken_soda.actions.append(action("transfer",{"source":"shaker","vessel":"glass"}))
	var flat:=Eval.evaluate(shaken_soda,definitions)
	check(has_tag(flat,"气泡不足") and flat.tier!="perfect","shaken carbonated ingredient gets a specific loss-of-fizz result")
	var short_mint:=mojito.duplicate(true)
	short_mint.vessels.glass.solids.sku_mint_leaf=1
	check(Eval.evaluate(short_mint,definitions).subscores.recipe<100,"solid ingredient counts participate in recipe adherence")
	var timed:=standard.duplicate(true)
	for i in range(40): timed.actions.insert(5,action("shake",{"vessel":"shaker","seconds":.5}))
	check(Eval.evaluate(timed,definitions).score<perfect.score,"excess mixing uses the configured gradual quality penalty")
	check(Eval.valid(perfect),"generated evaluation passes persistence validation")
	var invalid:=perfect.duplicate(true)
	invalid.attributes.sweetness=1000
	check(not Eval.valid(invalid),"corrupt saved attributes are rejected")
	# Exercise native finish -> atomic save -> result popup -> details -> restore.
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	var wallet_before: int=SlotWallet.balance
	await make_drink({"gin":30,"lime":20,"syrup":10})
	check(bench.data.result.evaluation.tier=="perfect" and is_instance_valid(bench.modal),"finishing pops up a saved perfect result")
	var cards: Array=bench.modal.find_children("FinishedDrinkCard","",true,false)
	check(cards.size()==1 and cards[0].preview.result.contents==bench.data.result.contents,"preview uses actual finished cup snapshot")
	await capture("40-quality-perfect")
	var saved: Dictionary=WorkbenchSession.snapshot()
	var inventory: Dictionary=Supplies.serialize()
	var receipt: Dictionary=saved.session.actions.back()
	check(WorkbenchSession.command(receipt.command_id,saved.session.id,"finish",{}) and Supplies.serialize()==inventory,"finish retry does not charge, reroll, or append a second result")
	check(Supplies.load_state() and WorkbenchSession.load_state() and same(WorkbenchSession.state.session.result,saved.session.result),"quality and attributes persist exactly across disk reload")
	bench._result_details()
	await settle()
	check(is_instance_valid(bench.modal) and same(WorkbenchSession.state,saved),"viewing detailed causes has no state mutation")
	await capture("41-quality-details")
	space()
	await settle()
	check(bench.modal.find_children("FinishedDrinkCard","",true,false).size()==1,"space returns from details to card")
	cancel()
	var old: Dictionary=WorkbenchSession.state.session.duplicate(true)
	old.result.erase("evaluation")
	check(WorkbenchSession._valid_session(old),"pre-evaluation finished saves remain supported")
	# A failed finish must leave the session mixing and must not persist an evaluation.
	bench._issue("start")
	bench._issue("withdraw",{"material":"gin","ml":15,"vessel":"glass"})
	var before: Dictionary=WorkbenchSession.snapshot()
	var path: String=Supplies.save_path
	Supplies.save_path=path+"/unwritable.json"
	check(not bench._issue("finish") and WorkbenchSession.state==before,"failed finish save rolls back status and evaluation together")
	Supplies.save_path=path
	await make_drink({"gin":30,"lime":20,"syrup":60})
	check(has_tag(bench.data.result.evaluation,"齁甜的"),"sweet defect appears in real result popup")
	await capture("42-quality-sweet")
	cancel()
	await make_drink({"syrup":60},false)
	check(bench.data.result.evaluation.tier=="terrible","terrible card uses purple-black quality")
	await capture("43-quality-terrible")
	DisplayServer.window_set_size(Vector2i(960,540))
	await settle()
	await capture("44-quality-small-window")
	check(SlotWallet.balance==wallet_before and not bench.data.result.sales,"quality does not produce sales or spend extra coins")
	print("WORKBENCH EVALUATION: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
