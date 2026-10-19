extends "res://tests/verify_workbench_drag.gd"

func _ready() -> void:
	# Native render checks must not steal keyboard focus from the developer.
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	super._ready()

func wait_animation() -> void:
	await get_tree().create_timer(1.7).timeout

func motion(point: Vector2) -> void:
	var event:=InputEventMouseMotion.new()
	event.position=local_point(point)
	event.button_mask=MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(event,true)

func run() -> void:
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	check(WorkbenchSession.capacity(bench.data,"glass")==120,"new coupe uses its own configured capacity")
	check(WorkbenchSession.recommended_cup({"glass":"高球杯"})=="highball" and WorkbenchSession.recommended_cup({"glass":"冷却鸡尾酒杯"})=="glass_cocktail_glass","recipe cup recommendation maps to available glassware")
	bench._issue("withdraw",{"material":"gin","ml":60,"vessel":"glass"})
	bench._issue("withdraw",{"material":"lime","ml":30,"vessel":"glass"})
	check(Liquid.surface_fraction(90,120,true,false)<Liquid.surface_fraction(90,300,true,false)-.05,"same actual drink occupies more of a smaller cup")
	SlotWallet.balance=300000
	check(Supplies.purchase("sku_mint_sprig") and Supplies.purchase("sku_cocktail_cherry"),"temporary test profile purchases garnish stock")
	bench._show_category("装饰")
	for id in ["garnish","lemon_slice","sku_mint_sprig","sku_cocktail_cherry"]:
		var before:=WorkbenchSession.remaining(id)
		from_pantry(id,"glass")
		check(WorkbenchSession.remaining(id)==before-1,"each garnish drag consumes its own SKU: "+id)
	check(WorkbenchSession.garnishes(bench.data.vessels.glass).size()==4,"four different garnishes coexist")
	await wait_animation()
	await capture("30-coupe-garnishes")
	var first_times: Array=bench.table.garnish_effects.glass.duplicate()
	from_pantry("lemon_slice","glass")
	check(WorkbenchSession.garnishes(bench.data.vessels.glass).size()==5 and bench.table.garnish_effects.glass[0]==first_times[0],"same garnish may be added again without replaying earlier decorations")
	var receipt: Dictionary=bench.data.actions.back()
	var state: Dictionary=WorkbenchSession.snapshot()
	var stock: Dictionary=Supplies.serialize()
	check(WorkbenchSession.command(receipt.command_id,bench.data.id,receipt.kind,receipt.payload) and Supplies.serialize()==stock,"retrying the same garnish command never charges twice")
	var path: String=Supplies.save_path
	Supplies.save_path=path+"/unwritable.json"
	check(not bench._issue("garnish",{"material":"garnish"}) and WorkbenchSession.state==state,"failed garnish save rolls back attachment and stock")
	Supplies.save_path=path
	for i in range(3): bench._act("garnish",{"material":"garnish"})
	state=WorkbenchSession.snapshot()
	check(not bench._issue("garnish",{"material":"garnish"}) and WorkbenchSession.state==state,"full rim rejects another garnish atomically")
	check(Supplies.load_state() and WorkbenchSession.load_state() and WorkbenchSession.garnishes(WorkbenchSession.state.session.vessels.glass).size()==8,"all garnish instances survive reload")
	var legacy: Dictionary=WorkbenchSession.state.session.duplicate(true)
	legacy.erase("vessel_capacities")
	for v in legacy.vessels.values():
		v.erase("ice_batches")
		v.erase("garnishes")
	check(WorkbenchSession._valid_session(legacy) and WorkbenchSession.capacity(legacy,"glass")==300,"legacy cup keeps its old capacity and single garnish representation")
	bench._issue("discard")
	bench._issue("start")
	bench._act("cup",{"cup":"highball"})
	bench._issue("withdraw",{"material":"lime","ml":80,"vessel":"glass"})
	bench._issue("withdraw",{"material":"gin","ml":60,"vessel":"glass"})
	bench._show_category("冰块")
	for i in range(3):
		from_pantry("cube","glass")
		await get_tree().create_timer(.15).timeout
	check(WorkbenchSession.ice_volume(bench.data.vessels.glass)==150,"three ice portions accumulate displacement")
	check(WorkbenchSession.amount(bench.data.vessels.glass)==140,"ice never fabricates liquid or changes actual ingredients")
	check(bench.table.ice_batch_effects.glass.size()==3,"each ice portion owns an arrival animation")
	await wait_animation()
	await capture("31-fuller-highball-ice")
	state=WorkbenchSession.snapshot()
	check(not bench._issue("cup",{"cup":"coupe"}) and WorkbenchSession.state==state,"smaller glass cannot silently lose existing contents")
	from_pantry("crushed","glass")
	check(WorkbenchSession.ice_batches(bench.data.vessels.glass).size()==4 and bench.data.vessels.glass.ice_batches[3].kind=="crushed","different ice types can coexist")
	state=WorkbenchSession.snapshot()
	check(not bench._issue("ice",{"vessel":"glass","ice":"cube"}) and WorkbenchSession.state==state,"full glass rejects excess ice without removing prior portions")
	check(Supplies.load_state() and WorkbenchSession.load_state() and WorkbenchSession.ice_batches(WorkbenchSession.state.session.vessels.glass).size()==4,"mixed ice quantities restore")
	bench._issue("discard")
	bench._issue("start")
	bench._show_category("基酒")
	from_pantry("gin","jigger")
	check(bench.measure.precise,"jigger enables live graduated measurement")
	bench.measure_waiting=false
	bench.measure.set_process(false)
	bench.measure.progress=.5
	check(is_equal_approx(bench.measure.current_ml(),22.5),"jigger live readout has exact fractional milliliters")
	await capture("32-graduated-jigger")
	bench.measure.progress=30/bench.measure.volume_limit()
	space()
	check(bench.data.vessels.jigger.contents.gin==30,"jigger gold region locks reference quantity")
	from_pantry("gin","shaker")
	check(not bench.measure.precise and bench.measure.volume_limit()>90,"free pour hides the gauge and may exceed one jigger")
	bench.measure_waiting=false
	bench.measure.set_process(false)
	bench.measure.progress=31.5/bench.measure.volume_limit()
	await capture("33-blind-free-pour")
	var gin_before:=WorkbenchSession.remaining("gin")
	click(button_named("停止倒入 · 空格"))
	check(bench.data.vessels.shaker.contents.gin==31.5 and WorkbenchSession.remaining("gin")==gin_before-31.5,"free pour records actual stopped dose without snapping to recipe")
	check(not bench.data.actions.back().payload.golden and bench.status_label.text.contains("31.5"),"free pour reveals actual amount only after stop")
	space()
	check(WorkbenchSession.remaining("gin")==gin_before-31.5,"repeat space cannot double debit free pour")
	if bench.data.lid: bench._act("lid")
	bench._act("ice",{"vessel":"shaker","ice":"cube"})
	if not bench.data.lid: bench._act("lid")
	bench._set_technique("shake")
	var center: Vector2=bench.table.POS.shaker
	pointer(local_point(center),true)
	await get_tree().create_timer(.3).timeout
	check(bench.table.shake_trail.is_empty(),"static lifted shaker has no fabricated motion trail")
	for i in range(30):
		motion(center+Vector2(0,sin(i*.5)*65))
		await get_tree().create_timer(.025).timeout
	check(not bench.table.shake_trail.is_empty(),"real front-back motion produces short localized trail")
	bench.table.set_process(false)
	await capture("34-shaker-motion")
	bench.table.set_process(true)
	pointer(local_point(center),false)
	await get_tree().create_timer(.3).timeout
	check(bench.table.shake_trail.is_empty() and bench.table.lift_blend==0,"release clears motion accents and returns shaker")
	var before_restart:=WorkbenchSession.snapshot()
	bench._restart()
	await settle()
	click(button_named("继续当前制作 · Esc"))
	check(not is_instance_valid(bench.modal) and WorkbenchSession.snapshot()==before_restart,"cancel remake by pointer preserves current cup")
	var stock_before_restart:=WorkbenchSession.remaining("gin")
	bench._restart()
	await settle()
	click(button_named("确认重做 · 空格"))
	check(bench.data.id!=before_restart.session.id and WorkbenchSession.remaining("gin")==stock_before_restart,"confirm remake by pointer starts one cup without refunding ingredients")
	bench._issue("withdraw",{"material":"gin","ml":15,"vessel":"glass"})
	bench._finish()
	await settle()
	click(button_named("查看依据 · R"))
	await settle()
	check(button_named("返回成品卡 · 空格")!=null,"details are reachable by pointer")
	click(button_named("返回成品卡 · 空格"))
	await settle()
	var finished_id: String=bench.data.id
	click(button_named("另起一杯 · 空格"))
	check(bench.data.id!=finished_id and bench.data.status=="mixing" and not is_instance_valid(bench.modal),"result new cup button works by pointer")
	print("WORKBENCH FINISHING: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
