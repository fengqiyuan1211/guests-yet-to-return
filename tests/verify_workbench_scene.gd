extends Node
const Art = preload("res://scripts/workbench_art.gd")
var failures: Array[String] = []
var count := 0
var home: Control
var bench: Control

func check(value: bool, message: String) -> void:
	count+=1
	if not value:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	if not WorkbenchSession.save_path.begins_with("/tmp/") or not GameSession.save_path.begins_with("/tmp/"):
		get_tree().quit(2)
		return
	check(preload("res://tests/workbench_fixture.gd").seed(Supplies,WorkbenchSession),"isolated warehouse fixture")
	TimeManager.set_process(false)
	call_deferred("run")

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func pointer(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position=point
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=pressed
	get_viewport().push_input(event,true)

func click(control: Control) -> void:
	var point:=control.get_global_transform_with_canvas()*(control.size*.5)
	pointer(point,true)
	pointer(point,false)

func table_click(point: Vector2) -> void:
	var position: Vector2=bench.table.get_global_transform_with_canvas()*point
	pointer(position,true)
	pointer(position,false)

func button_named(text: String) -> Button:
	var queue: Array[Node]=[bench]
	while not queue.is_empty():
		var node: Node=queue.pop_front()
		if node is Button and node.is_visible_in_tree() and not node.is_queued_for_deletion() and node.text.contains(text): return node
		for child in node.get_children(): queue.append(child)
	return null

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await get_tree().create_timer(.25).timeout
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute("/tmp/workbench-v2-preview")
	get_viewport().get_texture().get_image().save_png("/tmp/workbench-v2-preview/"+name+".png")

func run() -> void:
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	for id in Art.CELLS:
		var texture: Texture2D=Art.texture(id)
		check(texture!=null and texture.get_width()>20 and texture.get_height()>20,"independent sprite loads: "+id)
	check(bench.table.background!=null,"background plate loads")
	await capture("01-workbench")
	var tabs: Array=["基酒","配料","装饰","杯子","冰块","器具"]
	for i in range(tabs.size()):
		click(bench.category_buttons[i])
		await settle()
		check(bench.category==tabs[i] and not bench.item_buttons.is_empty(),"native pantry category: "+tabs[i])
	click(bench.category_buttons[0])
	await settle()
	var stock: Dictionary=WorkbenchSession.state.stock.duplicate(true)
	click(bench.item_buttons.gin)
	await settle()
	check(bench.table.bottle=="gin" and WorkbenchSession.state.stock==stock,"bottle selection is free of consumption")
	var bottle_point: Vector2=bench.table.bottle_rect("gin").get_center()
	pointer(bench.table.get_global_transform_with_canvas()*bottle_point,true)
	var drag:=InputEventMouseMotion.new()
	drag.position=bench.table.get_global_transform_with_canvas()*bench.table.POS.jigger
	drag.button_mask=MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(drag,true)
	pointer(drag.position,false)
	await settle()
	check(is_instance_valid(bench.measure),"drag bottle starts measure without confirmation")
	check(bench.table.pouring and WorkbenchSession.state.stock==stock,"pour animation does not commit preview dose")
	# Freeze both the delayed animation gate and the gauge before the screenshot.
	# Otherwise the gate restarts the gauge during capture and changes the dose.
	bench.measure_waiting=false
	bench.measure.set_process(false)
	bench.measure.progress=bench.measure.target/bench.measure.volume_limit()
	bench.measure.queue_redraw()
	await capture("02-pouring")
	var key:=InputEventKey.new()
	key.keycode=KEY_SPACE
	key.physical_keycode=KEY_SPACE
	key.pressed=true
	get_viewport().push_input(key,true)
	await settle()
	check(WorkbenchSession.state.stock.gin==570 and WorkbenchSession.state.session.vessels.jigger.contents.gin==30,"space confirms actual dose once")
	# Drag the actual jigger across the tabletop, not a surrogate UI button.
	var source: Vector2=bench.table.POS.jigger
	var destination: Vector2=bench.table.POS.shaker
	pointer(bench.table.get_global_transform_with_canvas()*source,true)
	for i in range(1,9):
		var move:=InputEventMouseMotion.new()
		move.position=bench.table.get_global_transform_with_canvas()*source.lerp(destination,i/8.0)
		move.button_mask=MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(move,true)
	pointer(bench.table.get_global_transform_with_canvas()*destination,false)
	await settle()
	check(WorkbenchSession.state.session.vessels.jigger.contents.is_empty() and WorkbenchSession.state.session.vessels.shaker.contents.get("gin")==30,"jigger drop transfers contents")
	check(WorkbenchSession.state.stock.gin==570,"drag transfer never debits inventory again")
	click(bench.category_buttons[4])
	await settle()
	click(bench.item_buttons.cube)
	table_click(bench.table.POS.shaker)
	await settle()
	check(WorkbenchSession.state.session.vessels.shaker.ice=="cube","ice selection targets real vessel")
	check(not WorkbenchSession.state.stock.has("cube"),"ice stays out of ingredient inventory")
	table_click(bench.table._rect("lid").get_center())
	await settle()
	check(WorkbenchSession.state.session.lid,"clicking separate lid closes shaker")
	table_click(bench.table.POS.shaker)
	check(WorkbenchSession.state.session.lid and bench.selected=="shaker","closed body grip does not reopen lid")
	await capture("03-closed-shaker")
	table_click(bench.table._rect("cap").get_center())
	await settle()
	check(not WorkbenchSession.state.session.lid,"cap click opens assembled shaker")
	click(bench.category_buttons[5])
	await settle()
	var strainer: Button=bench.item_buttons.strainer
	pointer(strainer.get_global_transform_with_canvas()*(strainer.size*.5),true)
	drag.position=bench.table.get_global_transform_with_canvas()*bench.table.POS.shaker
	get_viewport().push_input(drag,true)
	pointer(drag.position,false)
	await settle()
	check(WorkbenchSession.state.session.vessels.glass.contents.get("gin")==30,"physical strainer filters selected shaker")
	check(WorkbenchSession.state.session.vessels.shaker.ice=="cube" and WorkbenchSession.state.session.vessels.glass.ice=="none","ice retained after physical filtering")
	click(bench.category_buttons[2])
	await settle()
	click(bench.item_buttons.garnish)
	table_click(bench.table.POS.jigger)
	check(WorkbenchSession.state.garnish_stock==20,"wrong garnish target consumes nothing")
	click(bench.item_buttons.garnish)
	table_click(bench.table.POS.glass)
	await settle()
	check(WorkbenchSession.state.session.vessels.glass.garnish and WorkbenchSession.state.garnish_stock==19,"garnish attaches to actual glass once")
	click(bench.category_buttons[3])
	await settle()
	click(bench.item_buttons.highball)
	check(WorkbenchSession.state.session.cup=="highball" and WorkbenchSession.state.session.vessels.glass.contents.get("gin")==30 and WorkbenchSession.state.session.vessels.glass.garnish,"cup replacement preserves drink")
	click(bench.category_buttons[5])
	await settle()
	click(bench.item_buttons.spoon)
	check(bench.technique=="stir" and bench.selected=="mixing","bar spoon enables circular stirring")
	click(bench.item_buttons.muddler)
	check(bench.technique=="muddle" and bench.selected=="glass","muddler enables pressing")
	table_click(bench.table.POS.glass)
	await settle()
	await capture("04-garnished")
	get_viewport().push_input(key,true)
	await settle()
	check(WorkbenchSession.state.session.status=="finished" and not WorkbenchSession.state.session.result.sales,"native finish freezes practice with no sale")
	bench._clear_modal()
	var snapshot: Dictionary=WorkbenchSession.state.duplicate(true)
	click(bench.category_buttons[0])
	await settle()
	click(bench.item_buttons.gin)
	check(WorkbenchSession.state==snapshot,"finished cup rejects taking new materials")
	# Test true scaled viewport input, not only proportional layout assertions.
	DisplayServer.window_set_size(Vector2i(960,540))
	await settle()
	click(bench.category_buttons[4])
	await settle()
	check(bench.category=="冰块","small viewport category hit testing")
	await capture("05-small-workbench")
	Navigation.go_to(&"menu")
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	check(WorkbenchSession.state==snapshot,"new presentation retains cross-page persistence")
	print("WORKBENCH SCENE: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
