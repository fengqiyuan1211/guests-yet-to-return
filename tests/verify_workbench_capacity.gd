extends "res://tests/verify_workbench_stir_audio.gd"

func _ready() -> void:
	if "--capacity-resume" in OS.get_cmdline_user_args():
		if not str(Supplies.save_path).begins_with("/tmp/"): get_tree().quit(2); return
		call_deferred("verify_restored")
		return
	super._ready()

func verify_restored() -> void:
	var s: Dictionary=WorkbenchSession.state.session
	check(WorkbenchSession.writable and s.get("status")=="finished","separate process restores completed cup")
	check(s.get("waste",{}).get("gin",0)>0 and s.get("result",{}).get("contents",{}).get("contents",{}).get("lime")==5,"separate process preserves waste and 5 ml actual pour")
	check(WorkbenchSession._valid_session(s),"durable partial transfers and discard history validate")
	print("CAPACITY RESTORE: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func op(kind: String, payload: Dictionary={}) -> bool:
	var ok: bool=bench._issue(kind,payload)
	check(ok,kind+": "+WorkbenchSession.last_error)
	return ok

func run() -> void:
	# All stock mutations below use only the base fixture's private /tmp profile.
	for item in Supplies.catalog.list_items():
		if item.kind=="ingredient": Supplies.inventory.purchase(item.id,4)
	check(Supplies._write(Supplies.inventory.serialize(),Supplies.workbench),"seed recipe ingredients")
	Supplies._sync_menu()
	Supplies.changed.emit()
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	var entries: Array=[]
	for id in ["last_word","mojito","gin_and_tonic","long_island_iced_tea","manhattan"]: entries.append({"id":id,"price":40})
	check(MenuCatalog.save_menu(entries,MenuCatalog.design),"publish all five standard test recipes")
	for entry in entries:
		var replace: String=bench.data.id
		op("select_recipe",{"recipe_id":entry.id,"replace_session_id":replace})
		var target: String="shaker" if entry.id=="last_word" else ("mixing" if entry.id=="manhattan" else "glass")
		for ice in bench.data.recipe.ice:
			for i in range(int(ceil(float(ice.amount)/50))): op("ice",{"vessel":target,"ice":"crushed" if str(ice.sku_id).contains("crushed") else "cube"})
		var expected:=0.0
		for material in bench.data.recipe.ingredients:
			var ml: float=bench.data.recipe.ingredients[material]
			op("withdraw",{"material":material,"ml":ml,"vessel":target})
			expected+=ml
		if target!="glass": op("filter",{"source":target,"vessel":"glass"})
		check(is_equal_approx(WorkbenchSession.amount(bench.data.vessels.glass),expected),entry.id+" full standard liquid fits with serving ice")
		check(WorkbenchSession._valid_session(bench.data),entry.id+" standard session valid")
		if entry.id=="gin_and_tonic":
			check(WorkbenchSession.ice_mass(bench.data.vessels.glass)==150 and WorkbenchSession.recipe_note(bench.data).contains("＝3份＝12块"),"gin tonic is 200 ml plus 3 ice portions / 12 cubes / 150 g")
			await get_tree().create_timer(1.25).timeout
			await capture("47-gin-tonic-standard-full")
	# Test overflow with two ingredients, preserving liquid ratio and stock.
	op("discard")
	op("start")
	op("cup",{"cup":"coupe"})
	op("withdraw",{"material":"gin","ml":90,"vessel":"mixing"})
	op("withdraw",{"material":"lime","ml":90,"vessel":"mixing"})
	op("spoon",{"target":"mixing"})
	for i in range(20): op("stir",{"vessel":"mixing","seconds":.5,"control":1})
	op("ice",{"vessel":"mixing","ice":"cube"})
	op("add_solid",{"material":"sku_mint_leaf","vessel":"mixing"})
	var stock: Dictionary=WorkbenchSession.state.stock.duplicate(true)
	bench._act("filter",{"source":"mixing","vessel":"glass"})
	check(WorkbenchSession.amount(bench.data.vessels.glass)==120 and WorkbenchSession.amount(bench.data.vessels.mixing)==60,"filter fills cup and leaves 60 ml")
	check(bench.data.vessels.glass.contents.gin==60 and bench.data.vessels.mixing.contents.gin==30,"partial pour preserves the blend ratio")
	check(WorkbenchSession.ice_mass(bench.data.vessels.mixing)==50 and bench.data.vessels.mixing.solids.size()==1,"partial filter retains ice and herbs")
	var once: Dictionary=WorkbenchSession.snapshot()
	var action: Dictionary=bench.data.actions.back()
	check(WorkbenchSession.command(action.command_id,bench.data.id,action.kind,action.payload) and WorkbenchSession.state==once,"retry partial pour cannot transfer twice")
	check(not bench._issue("transfer",{"source":"mixing","vessel":"glass"}) and WorkbenchSession.state==once,"already full cup leaves source untouched")
	check(WorkbenchSession.state.stock==stock,"container transfer never consumes stock")
	var rule: Dictionary=bench.Evaluation.config().rules.get("workbench_practice",{"mix":"shake"})
	var trace: Dictionary=bench.Evaluation.replay(bench.data.actions,rule,WorkbenchSession.MATERIALS)
	check(is_equal_approx(trace.traced,120),"quality replay counts only poured portion")
	await get_tree().create_timer(1.25).timeout
	await capture("48-partial-filter")
	# Native drag serving glass to basin empties only this container.
	var source_before: Dictionary=bench.data.vessels.mixing.duplicate(true)
	drag_between(local_point(bench.table._rect("glass").position+Vector2(90,215)),local_point(bench.table.DRAIN_RECT.get_center()))
	check(WorkbenchSession.amount(bench.data.vessels.glass)==0 and bench.data.vessels.mixing==source_before,"native basin drag empties one vessel")
	check(bench.data.waste.gin==60 and bench.data.waste.lime==60 and WorkbenchSession.state.stock==stock,"discard records waste without refunds")
	check(WorkbenchSession._valid_session(bench.data),"waste plus retained liquid balances withdrawals")
	once=WorkbenchSession.snapshot()
	action=bench.data.actions.back()
	check(WorkbenchSession.command(action.command_id,bench.data.id,action.kind,action.payload) and WorkbenchSession.state==once,"dump command retry does not discard again")
	check(WorkbenchSession.load_state() and WorkbenchSession.state==once,"partial pour and waste restore exactly")
	trace=bench.Evaluation.replay(bench.data.actions,rule,WorkbenchSession.MATERIALS)
	check(trace.traced==0,"dumped drink is removed from quality replay")
	await get_tree().create_timer(1.25).timeout
	await capture("49-disposal-basin")
	# Test unfiltered overflow with whole ice pieces, not fractional ghost cubes.
	op("withdraw",{"material":"gin","ml":100,"vessel":"mixing"})
	op("transfer",{"source":"mixing","vessel":"glass"})
	check(is_equal_approx(WorkbenchSession.amount(bench.data.vessels.glass)+WorkbenchSession.ice_volume(bench.data.vessels.glass),120),"unfiltered overflow fills remaining space")
	check(WorkbenchSession.ice_mass(bench.data.vessels.glass)==25 and WorkbenchSession.ice_mass(bench.data.vessels.mixing)==25,"two whole cubes move and two stay")
	check(bench.data.vessels.glass.ice_batches[0].pieces==2,"partial ice batch renders actual piece count")
	check(WorkbenchSession.load_state() and WorkbenchSession._valid_session(WorkbenchSession.state.session),"split ice survives reload")
	# All four vessels accept disposal; failed disk writes remain atomic.
	var save_path: String=Supplies.save_path
	once=WorkbenchSession.snapshot()
	Supplies.save_path=save_path+"/missing.json"
	check(not bench._issue("empty",{"vessel":"glass"}) and WorkbenchSession.state==once,"failed disposal save leaves contents and stock intact")
	Supplies.save_path=save_path
	for id in ["glass","mixing","jigger","shaker"]:
		if WorkbenchSession.amount(bench.data.vessels[id])<=0: op("withdraw",{"material":"gin","ml":10,"vessel":id})
		if id=="shaker": op("lid")
		var grip: Vector2=bench.table._rect(id).position+Vector2(70,200) if id in ["glass","mixing"] else bench.table.POS[id]
		drag_between(local_point(grip),local_point(bench.table.DRAIN_RECT.get_center()))
		check(WorkbenchSession.amount(bench.data.vessels[id])==0 and WorkbenchSession.ice_mass(bench.data.vessels[id])==0,id+" emptied")
	# Bottle pours also clamp, debit and log only the amount that fits.
	op("withdraw",{"material":"gin","ml":115,"vessel":"glass"})
	var remaining: float=WorkbenchSession.remaining("lime")
	op("withdraw",{"material":"lime","ml":30,"vessel":"glass"})
	check(WorkbenchSession.amount(bench.data.vessels.glass)==120 and is_equal_approx(WorkbenchSession.remaining("lime"),remaining-5),"bottle overflow takes only 5 ml from stock")
	check(bench.data.actions.back().actual_ml==5 and bench.data.actions.back().payload.ml==30,"actual quantity separate from idempotent request")
	check(WorkbenchSession._valid_session(bench.data),"all transfers and waste remain balanced")
	op("finish")
	check(bench.data.result.waste.gin>0 and bench.data.result.contents.contents.lime==5,"result retains earlier waste and final drink")
	# Only equipment buttons create help; navigation/category/ingredients do not.
	for button in bench.category_buttons: check(button.get_script()==null and button.tooltip_text.is_empty(),"category has no popup")
	bench._show_category("配料")
	for button in bench.item_buttons.values(): check(button.get_script()==null and button.tooltip_text.is_empty(),"ingredient has no help popup")
	check(bench.ToolHelp.popup("")==null,"empty tooltip cannot create a blank window")
	bench._show_category("器具")
	check(bench.item_buttons.spoon.tooltip_text.contains("吧勺"),"tool usage help remains")
	bench._show_category("冰块")
	await get_tree().create_timer(1.25).timeout
	await capture("50-explicit-ice-portions")
	print("WORKBENCH CAPACITY: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
