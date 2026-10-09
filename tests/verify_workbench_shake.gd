extends "res://tests/verify_workbench_scene.gd"

func _ready() -> void:
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	super._ready()

func point(local: Vector2) -> Vector2:
	return bench.table.get_global_transform_with_canvas()*local

func motion(local: Vector2) -> void:
	var event:=InputEventMouseMotion.new()
	event.position=point(local)
	event.button_mask=MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(event,true)

func shakes() -> int:
	var result:=0
	for action in WorkbenchSession.state.session.actions:
		if action.kind=="shake": result+=1
	return result

func run() -> void:
	var recognizer=preload("res://scripts/workbench_shake_gesture.gd").new()
	var false_positive:=false
	for i in range(30): false_positive=false_positive or recognizer.sample(Vector2(25,0),.02,i*.02)
	check(not false_positive,"fast one-way movement is carrying rather than shaking")
	recognizer.reset()
	for i in range(40): false_positive=false_positive or recognizer.sample(Vector2(1 if i%2==0 else -1,0),.003,i*.003)
	check(not false_positive,"tiny high-speed pointer jitter cannot earn shake time")
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	bench._issue("withdraw",{"material":"gin","ml":30})
	bench._act("transfer",{"source":"jigger","vessel":"shaker"})
	bench._issue("withdraw",{"material":"lime","ml":20})
	bench._act("transfer",{"source":"jigger","vessel":"shaker"})
	bench._act("ice",{"vessel":"shaker","ice":"cube"})
	bench._act("lid")
	bench._set_technique("shake")
	await get_tree().create_timer(1.2).timeout
	var before_stock: Dictionary=WorkbenchSession.state.stock.duplicate(true)
	var before_contents: Dictionary=WorkbenchSession.state.session.vessels.duplicate(true)
	var center: Vector2=bench.table.POS.shaker
	pointer(point(center),true)
	await get_tree().create_timer(.3).timeout
	check(bench.table.lift_blend>.95,"pressing closed shaker lifts it from the counter")
	check(shakes()==0,"holding a lifted shaker does not count as shaking")
	for i in range(30):
		motion(center+Vector2(sin(i*.6)*60,0))
		await get_tree().create_timer(.015).timeout
	check(shakes()>0,"horizontal back-and-forth now counts as shaking")
	for i in range(40):
		motion(center+Vector2(0,sin(i*.5)*65))
		await get_tree().create_timer(.02).timeout
	check(shakes()>0,"vertical pointer strokes record front-back shaking")
	pointer(point(center),false)
	await get_tree().create_timer(.4).timeout
	var old_shakes:=shakes()
	pointer(point(center),true)
	await get_tree().create_timer(.3).timeout
	for i in range(25):
		motion(center+Vector2(i*2,0))
		await get_tree().create_timer(.025).timeout
	pointer(point(center+Vector2(48,0)),false)
	check(shakes()==old_shakes,"slow one-way carry never counts as shaking")
	await get_tree().create_timer(.4).timeout
	pointer(point(center),true)
	await get_tree().create_timer(.3).timeout
	var elsewhere:=Vector2(865,340)
	motion(elsewhere)
	await get_tree().create_timer(.2).timeout
	check((bench.table.shaker_pose()*center).distance_to(elsewhere+Vector2(0,-45))<15,"lifted shaker follows pointer into a different part of the table")
	for i in range(32):
		motion(elsewhere+Vector2(1,.8)*sin(i*.6)*55)
		await get_tree().create_timer(.02).timeout
	check(shakes()>old_shakes and not bench.table.moving_shaker,"diagonal oscillation far to the right remains shake rather than permanently switching to pour")
	bench.table.set_process(false)
	await capture("50-free-position-shake")
	bench.table.set_process(true)
	var active_shakes:=shakes()
	await get_tree().create_timer(.3).timeout
	check(not bench.table.motion_is_active() and shakes()==active_shakes,"pausing movement stops shake feedback and accounting")
	check(WorkbenchSession.state.session.lid,"shaker remains assembled during movement")
	await capture("12-shake-near")
	pointer(point(center),false)
	await get_tree().create_timer(.4).timeout
	check(bench.table.lift_blend==0 and not bench.table.dragging,"release settles shaker back on counter")
	check(bench.table.shaker_pose().is_equal_approx(Transform2D.IDENTITY),"landing restores original prop transform")
	check(WorkbenchSession.state.stock==before_stock,"shaking does not consume warehouse ingredients")
	for vessel in before_contents:
		var after: Dictionary=WorkbenchSession.state.session.vessels[vessel]
		check(after.ice_batches==before_contents[vessel].ice_batches,"shaking preserves ice in "+vessel)
		for material in before_contents[vessel].contents:
			check(is_equal_approx(float(after.contents.get(material,0)),float(before_contents[vessel].contents[material])),"mixing changes layers but preserves quantity: "+material)
	pointer(point(center),true)
	await get_tree().create_timer(.3).timeout
	bench.table._notification(Control.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await get_tree().create_timer(.4).timeout
	check(not bench.table.dragging and bench.table.lift_blend==0,"focus loss safely returns held shaker")
	bench._act("lid")
	pointer(point(center),true)
	await get_tree().create_timer(.3).timeout
	check(bench.table.lift_blend==0,"unsealed shaker cannot enter lifted shake mode")
	pointer(point(center),false)
	bench._act("filter",{"source":"shaker","vessel":"glass"})
	await get_tree().create_timer(1.2).timeout
	await capture("13-soft-liquid")
	print("WORKBENCH SHAKE: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
