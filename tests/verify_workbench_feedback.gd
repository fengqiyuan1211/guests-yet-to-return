extends "res://tests/verify_workbench_drag.gd"
const Notes=preload("res://scripts/workbench_notes.gd")

func _ready() -> void:
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	super._ready()

func run() -> void:
	WorkbenchSession.reset_game()
	SlotWallet.balance=300000
	SlotWallet.persist()
	check(Supplies.purchase("sku_mint_leaf"),"buy test leaf stock")
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	bench._act("cup",{"cup":"highball"})
	var original: Dictionary=bench.data.recipe.duplicate(true)
	var small: Dictionary=bench.data.duplicate(true)
	small.vessels.mixing.contents={"gin":10}
	small.consumed={"sku_gin_london_dry":10}
	check(Notes.text_for(small,WorkbenchSession).contains("待加 20 ml"),"partial dose shows remaining amount without calling it a failure")
	bench._issue("withdraw",{"material":"gin","ml":35,"vessel":"mixing"})
	check(bench.feedback_text.text.contains("35 ml") and bench.feedback_text.text.contains("搅拌杯"),"liquid addition says exact amount and destination")
	check(bench.note.text.contains("多加 5 ml"),"overdose annotated against frozen reference")
	bench._issue("withdraw",{"material":"vodka","ml":27.5,"vessel":"glass"})
	check(bench.note.text.contains("额外 伏特加 27.5 ml") and bench.note.text.contains("[b]"),"extra liquid has contrasting typography and precise amount")
	bench._act("add_solid",{"material":"sku_mint_leaf","vessel":"glass"})
	check(bench.feedback_text.text.contains("薄荷叶 1") and bench.note.text.contains("额外 薄荷叶 1"),"solid addition reports its own unit")
	bench._act("garnish",{"material":"garnish"})
	bench._act("garnish",{"material":"garnish"})
	check(bench.note.text.contains("额外 青柠角 2 块") and bench.feedback_text.text.contains("青柠角 1 块"),"garnish cumulative quantity differs from per-addition feedback")
	var stock: Dictionary=WorkbenchSession.state.stock.duplicate(true)
	for i in range(3): bench._act("ice",{"vessel":"glass","ice":"cube"})
	check(WorkbenchSession.ice_mass(bench.data.vessels.glass)==150 and WorkbenchSession.ice_volume(bench.data.vessels.glass)==150,"three portions give exactly 150 g")
	check(bench.feedback_text.text.contains("50 g") and bench.feedback_text.text.contains("150 g") and bench.note.text.contains("现有 150 g"),"ice portion and cumulative grams agree")
	var receipt: Dictionary=bench.data.actions.back()
	var saved: Dictionary=WorkbenchSession.snapshot()
	var path: String=Supplies.save_path
	Supplies.save_path=path+"/unwritable.json"
	check(not bench._issue("ice",{"vessel":"glass","ice":"crushed"}) and WorkbenchSession.state==saved,"failed ice save cannot add mass or change note")
	Supplies.save_path=path
	WorkbenchSession.last_error=""
	check(WorkbenchSession.command(receipt.command_id,bench.data.id,receipt.kind,receipt.payload) and WorkbenchSession.state==saved,"ice receipt retry never adds mass twice")
	check(WorkbenchSession.state.stock==stock,"ice policy stays outside ingredient stock ledger")
	check(WorkbenchSession.load_state() and WorkbenchSession.ice_mass(WorkbenchSession.state.session.vessels.glass)==150,"ice grams survive save/reload")
	var legacy: Dictionary=bench.data.duplicate(true)
	legacy.vessels.glass.ice_batches=[{"kind":"cube","volume":40}]
	check(WorkbenchSession._valid_session(legacy) and WorkbenchSession.ice_mass(legacy.vessels.glass)==40,"legacy ice remains at original quantity")
	var bad: Dictionary=legacy.duplicate(true)
	bad.vessels.glass.ice_batches[0].mass_g=-1
	check(not WorkbenchSession._valid_session(bad),"invalid mass rejected on load")
	bench._act("filter",{"source":"mixing","vessel":"glass"})
	check(bench.feedback_text.text.contains("35 ml") and bench.note.text.count("多加 5 ml")==1,"transfer reports amount without counting material twice")
	var pose: Dictionary=bench.table.transfer_pose("mixing","glass",.5)
	var mouth: Vector2=bench.table.transfer_lip("mixing",pose.rect,pose.angle)
	check(pose.angle>0 and mouth.x<bench.table.rim_point("glass").x and mouth.y<bench.table.rim_point("glass").y,"mixing spout tilts right and pours downward into glass")
	check(bench.table.transfer_pose("jigger","mixing",.5).angle<0,"leftward recipient uses opposite tilt")
	bench.table.animation_progress=.5
	bench.table.set_process(false)
	await capture("65-mixing-pours-right")
	bench.table.set_process(true)
	await get_tree().create_timer(1.2).timeout
	for id in ["gin","rum","vodka","lime","syrup"]: bench._place_material(id)
	check(WorkbenchSession.state.table_materials.size()==5,"five enlarged bottles still fit")
	check(bench.table.bottle_rect("gin").size==Vector2(108,270),"table bottle has larger physical scale")
	bench._issue("withdraw",{"material":"gin","ml":500,"vessel":"shaker"})
	bench._issue("withdraw",{"material":"gin","ml":65,"vessel":"jigger"})
	check(WorkbenchSession.remaining("gin")==0 and bench.feedback_text.text.contains("65 ml") and bench.feedback_text.text.contains("已用完") and bench.restock_button.visible,"last pour reports amount and offers restock")
	check(not bench.item_buttons.has("gin"),"empty pantry material disappears")
	check(bench.data.recipe==original,"actual changes never overwrite recipe")
	await capture("66-extra-ingredients-restock")
	var cup_id: String=bench.data.id
	var vessels: Dictionary=bench.data.vessels.duplicate(true)
	click(bench.restock_button)
	await settle()
	check(is_instance_valid(bench.external_page) and bench.external_page.selected_id=="sku_gin_london_dry","restock button opens shop at depleted SKU")
	var gold:=SlotWallet.balance
	check(Supplies.purchase("sku_gin_london_dry"),"purchase uses real shop inventory service")
	bench.external_page.close_requested.emit()
	await settle()
	check(bench.data.id==cup_id and bench.data.vessels==vessels,"shop round trip preserves half-finished drink")
	check(WorkbenchSession.remaining("gin")>0 and bench.item_buttons.has("gin") and not bench.restock_button.visible and SlotWallet.balance<gold,"purchase restores pantry and clears depleted state")
	for uniform in ["day_texture","night_texture","dawn_texture"]:
		var painting: Texture2D=bench.table.lighting.material.get_shader_parameter(uniform)
		check(painting!=null and painting.resource_path!="res://assets/workbench/background.png","dedicated time painting imported: "+uniform)
	for hour in [0,5,7,12,17,18,20,23]:
		TimeManager.minutes_since_midnight=hour*60
		await settle()
		check(bench.table.lighting.light_weights==home.get_node("Background").light_weights,"clock background follows saloon at %s:00" % hour)
		if hour in [5,12,18,23]: await capture("67-workbench-time-%s" % hour)
	var lighting_state: Dictionary=TimeManager.snapshot()
	TimeManager.minutes_since_midnight=18*60
	TimeManager.is_open=false
	check(TimeManager.start_early(),"clock fast-forward starts")
	TimeManager._process(2)
	await settle()
	check(bench.table.lighting.light_weights==home.get_node("Background").light_weights,"background agrees during accelerated clock")
	TimeManager.restore(lighting_state)
	var mojito: Dictionary=bench.data.duplicate(true)
	mojito.recipe=WorkbenchSession.recipe_snapshot(MenuCatalog.get_recipe("mojito"))
	check(Notes.text_for(mojito,WorkbenchSession).contains("额外出品冰 方冰 150 g"),"wrong ice type remains visible against recipe")
	for vessel in mojito.vessels.values():
		for batch in vessel.get("ice_batches",[]): batch.kind="crushed"
	check(Notes.text_for(mojito,WorkbenchSession).contains("碎冰现有 150 g / 配方 150 g"),"recipe grams and actual mass use same unit")
	bench._issue("discard")
	bench._issue("start")
	bench._act("cup",{"cup":"highball"})
	bench._issue("withdraw",{"material":"soda","ml":190,"vessel":"glass"})
	for i in range(3): bench._act("ice",{"vessel":"glass","ice":"cube"})
	check(WorkbenchSession.amount(bench.data.vessels.glass)==190 and WorkbenchSession.ice_mass(bench.data.vessels.glass)==150,"highball fits long-island liquid and ice quantities")
	DisplayServer.window_set_size(Vector2i(960,540))
	await settle()
	await capture("68-feedback-small-window")
	print("WORKBENCH FEEDBACK: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
