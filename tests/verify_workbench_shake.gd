extends "res://tests/verify_workbench_scene.gd"

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
	for i in range(20):
		motion(center+Vector2(sin(i*.6)*60,0))
		await get_tree().create_timer(.015).timeout
	check(shakes()==0,"horizontal movement does not count as front-back shaking")
	for i in range(40):
		motion(center+Vector2(0,sin(i*.5)*65))
		await get_tree().create_timer(.02).timeout
	check(shakes()>0,"vertical pointer strokes record front-back shaking")
	motion(center+Vector2(0,-65))
	await get_tree().create_timer(.15).timeout
	var far: Transform2D=bench.table.shaker_pose()
	await capture("11-shake-far")
	motion(center+Vector2(0,65))
	await get_tree().create_timer(.15).timeout
	var near: Transform2D=bench.table.shaker_pose()
	check(near.get_scale().x>far.get_scale().x,"shaker grows when pulled toward player")
	check((near*center).y>(far*center).y,"front-back depth changes projected position")
	check(not is_equal_approx(near.get_rotation(),far.get_rotation()),"fore-aft stroke changes whole-assembly tilt")
	check(WorkbenchSession.state.session.lid,"shaker remains assembled during movement")
	await capture("12-shake-near")
	pointer(point(center),false)
	await get_tree().create_timer(.4).timeout
	check(bench.table.lift_blend==0 and not bench.table.dragging,"release settles shaker back on counter")
	check(bench.table.shaker_pose().is_equal_approx(Transform2D.IDENTITY),"landing restores original prop transform")
	check(WorkbenchSession.state.stock==before_stock and WorkbenchSession.state.session.vessels==before_contents,"animation does not consume or move ingredients")
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
