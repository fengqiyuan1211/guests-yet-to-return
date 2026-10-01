extends "res://tests/verify_workbench_scene.gd"
const Liquid = preload("res://scripts/workbench_liquid.gd")

func drag_between(start: Vector2, destination: Vector2) -> void:
	pointer(start,true)
	for i in range(1,9):
		var motion:=InputEventMouseMotion.new()
		motion.position=start.lerp(destination,i/8.0)
		motion.button_mask=MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion,true)
	pointer(destination,false)

func local_point(point: Vector2) -> Vector2:
	return bench.table.get_global_transform_with_canvas()*point

func from_pantry(id: String, target: String) -> void:
	var item: Button=bench.item_buttons[id]
	drag_between(item.get_global_transform_with_canvas()*(item.size*.5),local_point(bench.table.POS[target]))

func space() -> void:
	var key:=InputEventKey.new()
	key.keycode=KEY_SPACE
	key.physical_keycode=KEY_SPACE
	key.pressed=true
	get_viewport().push_input(key,true)

func cancel() -> void:
	var key:=InputEventKey.new()
	key.keycode=KEY_ESCAPE
	key.pressed=true
	get_viewport().push_input(key,true)

func run() -> void:
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	var initial_stock: Dictionary=WorkbenchSession.state.stock.duplicate(true)
	from_pantry("gin","jigger")
	check(is_instance_valid(bench.measure),"native pantry drag starts measure directly")
	if not is_instance_valid(bench.measure): get_tree().quit(1); return
	check(WorkbenchSession.state.table_materials==["gin"],"drag creates one persistent bottle")
	check(WorkbenchSession.state.stock==initial_stock,"starting animation never debits stock")
	bench.measure_waiting=false
	bench.measure.set_process(false)
	bench.measure.progress=.67
	await get_tree().create_timer(.35).timeout
	check(bench.table.preview_amount>0 and bench.table.pour_blend>.9,"bottle tilt and preview liquid advance")
	check(WorkbenchSession.amount(WorkbenchSession.state.session.vessels.jigger)==0,"preview liquid is not committed contents")
	await capture("06-drag-measure")
	bench.measure.progress=.67
	space()
	space()
	check(WorkbenchSession.state.stock.gin==570,"space twice debits once")
	check(WorkbenchSession.state.session.vessels.jigger.contents.gin==30,"golden dose committed")
	await settle()
	drag_between(local_point(bench.table.POS.jigger),local_point(bench.table.POS.glass))
	check(WorkbenchSession.state.session.vessels.glass.contents.gin==30,"native transfer commits glass contents")
	check(WorkbenchSession.state.stock.gin==570,"transfer has no inventory debit")
	await get_tree().create_timer(.4).timeout
	var intermediate := Liquid.volume(bench.table.contents_for("glass"))
	check(intermediate>0 and intermediate<30,"glass fills progressively during transfer")
	await get_tree().create_timer(.8).timeout
	var clear_color := Liquid.color(bench.table.contents_for("glass"))
	click(bench.category_buttons[1])
	await settle()
	from_pantry("lime","jigger")
	check(is_instance_valid(bench.measure) and bench.measure.target==20,"recipe amount selected for lime automatically")
	cancel()
	check(WorkbenchSession.state.stock.lime==600 and WorkbenchSession.state.session.vessels.jigger.contents.is_empty(),"Escape cancels only pending dose")
	check(WorkbenchSession.state.table_materials==["gin","lime"],"cancel leaves bottle on table")
	drag_between(local_point(bench.table.bottle_rect("lime").get_center()),local_point(bench.table.POS.jigger))
	check(is_instance_valid(bench.measure),"resident bottle can be reused by dragging")
	bench.measure_waiting=false
	bench.measure.set_process(false)
	bench.measure.progress=.67
	space()
	await settle()
	drag_between(local_point(bench.table.POS.jigger),local_point(bench.table.POS.glass))
	await get_tree().create_timer(1.2).timeout
	var mixed_color := Liquid.color(bench.table.contents_for("glass"))
	check(mixed_color!=clear_color and mixed_color.a>clear_color.a,"lime visibly changes clear drink color and opacity")
	check(is_equal_approx(Liquid.volume(bench.table.contents_for("glass")),50),"visible glass volume converges to actual ml")
	await capture("07-colored-glass")
	click(bench.category_buttons[0])
	await settle()
	click(bench.item_buttons.rum)
	click(bench.item_buttons.vodka)
	click(bench.category_buttons[1])
	await settle()
	click(bench.item_buttons.soda)
	check(WorkbenchSession.state.table_materials.size()==5,"five distinct bottles coexist")
	var before: Dictionary=WorkbenchSession.state.duplicate(true)
	from_pantry("syrup","jigger")
	check(not is_instance_valid(bench.measure) and WorkbenchSession.state==before,"sixth bottle rejected without dose or replacing another bottle")
	await capture("08-five-bottles")
	drag_between(local_point(bench.table.bottle_rect("gin").get_center()),local_point(Vector2(1400,600)))
	check(WorkbenchSession.state.table_materials.size()==4 and not WorkbenchSession.state.table_materials.has("gin"),"dragging bottle back frees slot")
	check(WorkbenchSession.state.session.vessels.glass.contents.gin==30,"returning bottle never removes poured gin")
	from_pantry("syrup","jigger")
	check(is_instance_valid(bench.measure) and WorkbenchSession.state.table_materials.size()==5,"freed slot accepts a different material")
	cancel()
	before=WorkbenchSession.state.duplicate(true)
	drag_between(local_point(bench.table.bottle_rect("soda").get_center()),local_point(bench.table._rect("spoon").get_center()))
	check(WorkbenchSession.state==before and not is_instance_valid(bench.measure),"invalid destination causes no dose")
	click(bench.category_buttons[4])
	await settle()
	from_pantry("cube","glass")
	check(WorkbenchSession.state.session.vessels.glass.ice=="cube","ice drag applies directly")
	click(bench.category_buttons[2])
	await settle()
	from_pantry("garnish","glass")
	check(WorkbenchSession.state.session.vessels.glass.garnish and WorkbenchSession.state.garnish_stock==19,"garnish drag applies once")
	var snapshot: Dictionary=WorkbenchSession.state.duplicate(true)
	Navigation.go_to(&"menu")
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	check(WorkbenchSession.state==snapshot and bench.table.materials==snapshot.table_materials,"page round trip preserves bottles, contents and stock")
	var disk: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(WorkbenchSession.save_path))
	check(disk.table_materials==snapshot.table_materials,"table arrangement is persisted with production state")
	var path: String=WorkbenchSession.save_path
	WorkbenchSession.save_path=path+"/unwritable.json"
	check(not WorkbenchSession.set_table_materials([]) and WorkbenchSession.state==snapshot,"failed arrangement save preserves all existing state")
	WorkbenchSession.save_path=path
	check(not WorkbenchSession.set_table_materials(["gin","gin"]),"duplicate bottles rejected by service")
	await capture("09-final-table")
	WorkbenchSession.last_error=""
	bench._issue("discard")
	bench._issue("start")
	click(bench.category_buttons[3])
	await settle()
	click(bench.item_buttons.highball)
	check(WorkbenchSession.state.session.cup=="highball","empty glass changes to highball through pantry")
	click(bench.category_buttons[1])
	await settle()
	bench.dose_overrides["lime"]=60
	from_pantry("lime","jigger")
	check(is_instance_valid(bench.measure) and bench.measure.target==60,"custom target survives direct drag flow")
	bench.measure.progress=.67
	space()
	await settle()
	drag_between(local_point(bench.table.POS.jigger),local_point(bench.table.POS.glass))
	await get_tree().create_timer(1.2).timeout
	check(WorkbenchSession.state.session.vessels.glass.contents.get("lime")==60,"highball receives measured liquid")
	await capture("10-highball-liquid")
	print("WORKBENCH DRAG: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
