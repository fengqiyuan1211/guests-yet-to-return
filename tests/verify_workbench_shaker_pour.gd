extends "res://tests/verify_workbench_drag.gd"

func _ready() -> void:
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	super._ready()

func wait_pour() -> void:
	await get_tree().create_timer(1.2).timeout

func stir_count() -> int:
	var count:=0
	for action in WorkbenchSession.state.session.actions:
		if action.kind=="stir": count+=1
	return count

func run() -> void:
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	bench._act("cup",{"cup":"highball"})
	check(not bench.table.prop_visible("spoon"),"spoon stored off table at rest")
	check(bench.table._hit(bench.table._rect("spoon").get_center())!="spoon","stored spoon has no invisible hit target")
	table_click(bench.table._rect("spoon").get_center())
	check(bench.technique=="shake","former spoon spot does not switch technique")
	bench._show_category("器具")
	check(bench.item_buttons.has("spoon"),"spoon remains available in tools menu")
	bench._issue("withdraw",{"material":"gin","ml":30,"vessel":"mixing"})
	from_pantry("spoon","mixing")
	check(bench.selected=="mixing" and bench.technique=="stir","menu spoon enables stirring on drop")
	var center: Vector2=bench.table.POS.mixing
	pointer(local_point(center+Vector2(35,0)),true)
	check(bench.table.prop_visible("spoon"),"inserted spoon remains visible while stirring")
	for i in range(1,31):
		var motion:=InputEventMouseMotion.new()
		motion.position=local_point(center+Vector2.from_angle(i*.2)*35)
		motion.button_mask=MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion,true)
		await get_tree().create_timer(.02).timeout
	pointer(local_point(center),false)
	check(stir_count()>0 and bench.table.prop_visible("spoon"),"stirring records time and spoon stays inserted on release")
	table_click(bench.table.spoon_geometry().handle)
	check(not bench.table.prop_visible("spoon"),"click exposed spoon handle to store it")
	# An open shaker can be directly dragged into the serving glass.
	bench._issue("withdraw",{"material":"lime","ml":22.5,"vessel":"shaker"})
	bench._set_technique("shake")
	var before_stock: Dictionary=WorkbenchSession.state.stock.duplicate(true)
	drag_between(local_point(bench.table.POS.shaker),local_point(bench.table.POS.glass))
	check(WorkbenchSession.state.session.vessels.glass.contents.get("lime")==22.5,"native open-shaker drag pours into glass")
	check(WorkbenchSession.state.session.vessels.shaker.contents.is_empty(),"open shaker drained")
	check(WorkbenchSession.state.stock==before_stock,"shaker pour does not debit warehouse twice")
	check(bench.table.animated_source=="shaker" and bench.table.animated_destination=="glass","shaker drag triggers pour animation")
	await wait_pour()
	# A closed three-piece shaker uncaps and uses its integrated strainer.
	bench._issue("withdraw",{"material":"gin","ml":30,"vessel":"shaker"})
	bench._act("ice",{"vessel":"shaker","ice":"cube"})
	bench._act("lid")
	before_stock=WorkbenchSession.state.stock.duplicate(true)
	pointer(local_point(bench.table.POS.shaker),true)
	await get_tree().create_timer(.3).timeout
	check(bench.table.lift_blend>.95 and not bench.table.moving_shaker,"closed shaker still lifts for front-back shaking")
	var event:=InputEventMouseMotion.new()
	event.position=local_point(bench.table.POS.glass)
	event.button_mask=MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(event,true)
	check(not bench.table.moving_shaker and bench.table._destination(bench.table.POS.glass)=="glass","closed shaker stays draggable and recognizes glass only as release destination")
	await capture("09-shaker-drag")
	pointer(local_point(bench.table.POS.glass),false)
	check(WorkbenchSession.state.session.vessels.glass.contents.get("gin")==30,"closed shaker pours through its built-in strainer")
	check(WorkbenchSession.state.session.vessels.shaker.ice=="cube" and WorkbenchSession.state.session.vessels.glass.ice=="none","built-in strainer retains ice")
	check(WorkbenchSession.state.session.lid,"fitted shaker filter remains attached after pour")
	check(WorkbenchSession.state.stock==before_stock,"closed pour consumes no extra inventory")
	var action: Dictionary=WorkbenchSession.state.session.actions.back()
	check(action.kind=="filter" and action.payload.get("integrated_strainer")==true,"pour uses explicit existing filter action and is recorded")
	bench.table.set_process(false)
	bench.table.animation_progress=.45
	bench.table.transition_progress=.45
	bench.table.queue_redraw()
	bench.table.animation_progress=.1
	check(is_equal_approx(Liquid.volume(bench.table.contents_for("glass")),22.5),"glass waits for stream before rising")
	bench.table.animation_progress=.8
	check(is_equal_approx(Liquid.volume(bench.table.contents_for("glass")),52.5),"glass reaches final level before shaker returns")
	bench.table.animation_progress=.45
	check(not bench.table.shaker_pour_pose().is_equal_approx(Transform2D.IDENTITY),"pour transforms body and fitted lid together")
	await capture("10-shaker-pour")
	bench.table.animation_progress=.76
	bench.table.queue_redraw()
	await capture("52-pour-last-drops")
	bench.table.set_process(true)
	await wait_pour()
	var finished: Dictionary=WorkbenchSession.snapshot()
	pointer(local_point(bench.table.POS.glass),false)
	check(WorkbenchSession.state==finished,"duplicate mouse release does not repeat transfer")
	check(WorkbenchSession.command(action.command_id,finished.session.id,action.kind,action.payload) and WorkbenchSession.state==finished,"retry remains idempotent")
	check(WorkbenchSession.load_state() and WorkbenchSession.state.session.vessels.glass.contents.lime==22.5,"poured cup and fractional volume restore")
	# Empty and invalid drops leave contents intact.
	drag_between(local_point(bench.table.POS.shaker),local_point(bench.table.POS.glass))
	check(WorkbenchSession.state==finished,"empty shaker cannot fabricate another serving")
	bench._act("lid")
	bench._issue("withdraw",{"material":"syrup","ml":10,"vessel":"shaker"})
	var before: Dictionary=WorkbenchSession.snapshot()
	drag_between(local_point(bench.table.POS.shaker),local_point(Vector2(800,610)))
	check(WorkbenchSession.state==before and not bench.table.moving_shaker,"invalid drop returns shaker without transferring")
	var free: float=WorkbenchSession.capacity(bench.data,"glass")-WorkbenchSession.amount(bench.data.vessels.glass)-WorkbenchSession.ice_volume(bench.data.vessels.glass)
	check(bench._issue("withdraw",{"material":"soda","ml":free,"vessel":"glass"}),"fill current glass capacity before rejection check")
	before=WorkbenchSession.snapshot()
	drag_between(local_point(bench.table.POS.shaker),local_point(bench.table.POS.glass))
	check(WorkbenchSession.state==before,"full receiving glass rejects pour atomically")
	# Failure to save also leaves both containers and stock intact.
	bench._issue("discard")
	bench._issue("start")
	bench._issue("withdraw",{"material":"gin","ml":30,"vessel":"shaker"})
	bench._act("lid")
	before=WorkbenchSession.snapshot()
	var path: String=Supplies.save_path
	Supplies.save_path=path+"/unwritable.json"
	drag_between(local_point(bench.table.POS.shaker),local_point(bench.table.POS.glass))
	check(WorkbenchSession.state==before,"failed pour save rolls back source destination and inventory")
	Supplies.save_path=path
	WorkbenchSession.last_error=""
	bench.status_label.text="拖动摇壶到右上角成品杯，松手倒酒。"
	await wait_pour()
	var panel: StyleBoxFlat=bench.context.get_theme_stylebox("panel")
	check(panel.bg_color.a==1 and panel.bg_color.get_luminance()>.8,"bottom hint has opaque pale background")
	check(bench.next_hint.get_theme_color("font_color").get_luminance()<.2 and bench.next_hint.get_theme_font_size("font_size")>=23,"instruction uses larger dark type")
	check(bench.status_label.get_theme_color("font_color").get_luminance()<.3,"action feedback is dark on same pale panel")
	await capture("11-clear-workbench-hints")
	bench._begin_measure("lime",20,"glass")
	bench.measure.set_process(false)
	bench.measure_waiting=false
	bench.measure.progress=bench.measure.target/bench.measure.volume_limit()
	bench.table.pour_blend=1
	await capture("12-clear-dosing-hints")
	cancel()
	# Small viewport retains drag hit targets.
	DisplayServer.window_set_size(Vector2i(960,540))
	await settle()
	drag_between(local_point(bench.table.POS.shaker),local_point(bench.table.POS.glass))
	check(WorkbenchSession.state.session.vessels.glass.contents.get("gin")==30,"scaled viewport shaker drag pours correctly")
	await wait_pour()
	await capture("13-clear-hints-small")
	print("SHAKER POUR: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
