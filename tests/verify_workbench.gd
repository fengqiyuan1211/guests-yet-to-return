extends Node
var failures: Array[String] = []
var count := 0
var home: Control
var bench: Control

func check(ok: bool, message: String) -> void:
	count += 1
	if not ok:
		failures.append(message)
		push_error(message)

func same(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func command(id: String, kind: String, payload: Dictionary = {}) -> bool:
	return WorkbenchSession.command(id,str(WorkbenchSession.state.session.get("id","")),kind,payload)

func _ready() -> void:
	if not WorkbenchSession.save_path.begins_with("/tmp/") or not SlotWallet.save_path.begins_with("/tmp/") or not StoryDialogue.save_path.begins_with("/tmp/") or not GameSession.save_path.begins_with("/tmp/"):
		get_tree().quit(2)
		return
	check(preload("res://tests/workbench_fixture.gd").seed(Supplies,WorkbenchSession),"isolated warehouse fixture")
	TimeManager.set_process(false)
	call_deferred("run")

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func click(control: Control) -> void:
	var e := InputEventMouseButton.new()
	e.position = control.get_global_transform_with_canvas() * (control.size*.5)
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	get_viewport().push_input(e,true)
	e = e.duplicate()
	e.pressed = false
	get_viewport().push_input(e,true)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/workbench-preview")
	get_viewport().get_texture().get_image().save_png("/tmp/workbench-preview/" + name + ".png")

func run() -> void:
	check(WorkbenchSession.reset_game(),"reset isolated practice")
	check(command("start","start"),"create practice")
	var sid: String = WorkbenchSession.state.session.id
	var stock: int = WorkbenchSession.state.stock.gin
	check(command("pour","withdraw",{"material":"gin","ml":18}),"withdraw 18")
	check(command("pour","withdraw",{"material":"gin","ml":18}),"duplicate command succeeds idempotently")
	check(WorkbenchSession.state.stock.gin == stock-18,"withdraw only once")
	check(not command("pour","withdraw",{"material":"gin","ml":19}),"reject id reuse with other payload")
	check(command("transfer","transfer",{"source":"jigger","vessel":"shaker"}),"transfer")
	check(WorkbenchSession.state.stock.gin == stock-18 and WorkbenchSession.amount(WorkbenchSession.state.session.vessels.shaker)==18,"transfer does not charge")
	check(not command("shake-open","shake",{"vessel":"shaker","seconds":.25}),"cannot shake open shaker")
	check(command("ice","ice",{"vessel":"shaker","ice":"cube"}),"add ice")
	check(command("ice-again","ice",{"vessel":"shaker","ice":"cube"}),"can add another portion of ice")
	check(command("lid","lid"),"close lid")
	check(command("shake","shake",{"vessel":"shaker","seconds":.25}),"closed shaker accepts motion")
	check(not command("filter-closed","filter",{"source":"shaker","vessel":"glass"}),"filter needs open lid")
	check(command("unlid","lid") and command("filter","filter",{"source":"shaker","vessel":"glass"}),"filter into glass")
	check(WorkbenchSession.state.session.vessels.shaker.ice=="cube" and WorkbenchSession.state.session.vessels.glass.ice=="none","filter retains ice")
	check(command("garnish","garnish") and command("finish","finish"),"finish practice")
	var completed: Dictionary = WorkbenchSession.state.session.result.duplicate(true)
	check(command("finish","finish"),"repeated finish returns original receipt")
	check(same(WorkbenchSession.state.session.result,completed),"result immutable")
	check(not command("after-finish","withdraw",{"material":"gin","ml":10}),"terminal cup cannot take materials")
	check(WorkbenchSession.load_state(),"reload completed snapshot")
	check(WorkbenchSession.state.session.id==sid and same(WorkbenchSession.state.session.result,completed),"reload preserves cup")
	check(command("new","start"),"new cup")
	check(WorkbenchSession.state.stock.gin==stock-18,"new cup no refund")
	check(not WorkbenchSession.command("stale",sid,"withdraw",{"material":"gin","ml":10}),"stale session rejected")
	check(command("fill","withdraw",{"material":"gin","ml":90}),"fill jigger")
	var before := JSON.stringify(WorkbenchSession.state)
	check(not command("overflow","withdraw",{"material":"gin","ml":1}),"overflow rejected")
	check(JSON.stringify(WorkbenchSession.state)==before,"failed operation changes nothing")
	var path := Supplies.save_path
	Supplies.save_path = "/tmp/workbench-no-such-directory/record.json"
	check(not command("bad-disk","discard"),"save failure reported")
	check(JSON.stringify(WorkbenchSession.state)==before,"disk failure does not mutate live state")
	Supplies.save_path = path
	check(command("discard","discard") and command("newer","start"),"discard then restart")
	check(WorkbenchSession.state.stock.gin==stock-108,"discard does not refund")
	check(command("persist","withdraw",{"material":"lime","ml":20}),"new cup material")
	var expected: Dictionary = WorkbenchSession.state.duplicate(true)
	WorkbenchSession.state = {}
	check(WorkbenchSession.load_state() and same(WorkbenchSession.state,expected),"inventory vessels actions receipts restore together")
	# Real routes and UI interactions, with existing systems held to their snapshots.
	home = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	var balance: int = SlotWallet.balance
	var story := JSON.stringify(StoryDialogue.progress)
	var menu := JSON.stringify(MenuCatalog.entries)
	var clock := TimeManager.snapshot()
	Navigation.go_to(&"mixing")
	await settle()
	bench = home.active_page
	check(bench.get_script().resource_path=="res://scripts/workbench.gd","mixing route opens workbench")
	check(bench.size.x > 0 and bench.surface.scale.x > 0,"page has usable layout")
	await capture("01-table")
	# Real pantry clicks select a bottle without consuming inventory.
	var pre_pick: Dictionary = WorkbenchSession.state.stock.duplicate(true)
	click(bench.item_buttons.gin)
	await settle()
	check(bench.table.bottle=="gin" and WorkbenchSession.state.stock==pre_pick,"pantry picks a bottle without withdrawing")
	await capture("02-materials")
	bench._begin_measure("gin",30)
	await settle()
	bench.measure_waiting=false
	bench.measure.set_process(false)
	bench.measure.progress=bench.measure.target/bench.measure.volume_limit()
	bench.measure.queue_redraw()
	await capture("03-measure")
	var key := InputEventKey.new()
	key.physical_keycode=KEY_SPACE
	key.keycode=KEY_SPACE
	key.pressed=true
	get_viewport().push_input(key,true)
	await settle()
	check(not is_instance_valid(bench.measure) and WorkbenchSession.state.session.vessels.jigger.contents.gin==30,"space locks golden amount")
	get_viewport().push_input(key,true)
	check(WorkbenchSession.state.session.vessels.jigger.contents.gin==30,"second space no double pour")
	# Under / over / timeout all record the indicated amount, never an extra charge.
	for sample in [[.2,3],[.9,13.5],[1.0,15]]:
		bench._begin_measure("soda",10)
		bench.measure.set_process(false)
		bench.measure.progress=sample[0]
		var soda_before: float = WorkbenchSession.state.stock.soda
		if sample[0] == 1.0:
			bench.measure._process(5.0)
		else:
			bench.measure.confirm()
		check(soda_before-WorkbenchSession.state.stock.soda==sample[1],"off-target / timeout uses actual amount")
	var cancel_stock: Dictionary = WorkbenchSession.state.stock.duplicate(true)
	bench._begin_measure("syrup",10)
	var cancel := InputEventKey.new()
	cancel.keycode=KEY_ESCAPE
	cancel.pressed=true
	get_viewport().push_input(cancel,true)
	check(not is_instance_valid(bench.modal) and WorkbenchSession.state.stock==cancel_stock and Navigation.current_route==&"mixing","Escape cancels uncommitted measurement, stays on workbench")
	bench._act("transfer",{"source":"jigger","vessel":"mixing"})
	bench._select("mixing")
	bench._set_technique("stir")
	# Pointer circles are sent through the viewport, not the business service.
	var center: Vector2 = bench.table.POS.mixing
	var e := InputEventMouseButton.new()
	e.position=bench.table.get_global_transform_with_canvas()*(center+Vector2(55,0))
	e.button_index=MOUSE_BUTTON_LEFT
	e.pressed=true
	get_viewport().push_input(e,true)
	for i in range(1,45):
		await get_tree().create_timer(.02).timeout
		var move := InputEventMouseMotion.new()
		move.position=bench.table.get_global_transform_with_canvas()*(center+Vector2.from_angle(i*.2)*55)
		move.button_mask=MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(move,true)
	e.pressed=false
	get_viewport().push_input(e,true)
	var stirred := false
	for action in WorkbenchSession.state.session.actions:
		if action.kind=="stir":
			stirred=true
	check(stirred,"mouse circular movement records stirring")
	bench._act("transfer",{"source":"mixing","vessel":"shaker"})
	bench._act("lid")
	bench._set_technique("shake")
	center=bench.table.POS.shaker
	e.position=bench.table.get_global_transform_with_canvas()*center
	e.pressed=true
	get_viewport().push_input(e,true)
	var action_count: int = WorkbenchSession.state.session.actions.size()
	await get_tree().create_timer(.1).timeout
	check(WorkbenchSession.state.session.actions.size()==action_count,"holding without movement does not advance technique")
	for i in range(1,40):
		await get_tree().create_timer(.02).timeout
		var move := InputEventMouseMotion.new()
		move.position=bench.table.get_global_transform_with_canvas()*(center+Vector2(0,sin(i*.5)*65))
		move.button_mask=MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(move,true)
	e.pressed=false
	get_viewport().push_input(e,true)
	var shaken := false
	for action in WorkbenchSession.state.session.actions:
		if action.kind=="shake":
			shaken=true
	check(shaken,"mouse alternating motion records shaking")
	await capture("04-shaker")
	bench._act("lid")
	var cup_snapshot := JSON.stringify(WorkbenchSession.state)
	Navigation.go_to(&"codex")
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench = home.active_page
	check(JSON.stringify(WorkbenchSession.state)==cup_snapshot,"page changes preserve exact half-made cup")
	check(SlotWallet.balance==balance and JSON.stringify(StoryDialogue.progress)==story and JSON.stringify(MenuCatalog.entries)==menu,"workbench leaves wallet story menu unchanged")
	check(TimeManager.snapshot()==clock,"workbench does not change clock")
	bench._act("filter",{"source":"shaker","vessel":"glass"})
	bench._finish()
	await settle()
	await capture("04-finish-confirm")
	WorkbenchSession.command("ui-finish",WorkbenchSession.state.session.id,"finish")
	bench._result()
	await settle()
	await capture("05-result")
	check(SlotWallet.balance==balance,"practice finish gives no money")
	DisplayServer.window_set_size(Vector2i(960,540))
	await settle()
	await capture("06-small-result")
	# Closing never interrupts an unrelated practice/result view.
	TimeManager.is_open=true
	home.service_started=true
	var closing_route: StringName=Navigation.current_route
	home._on_business_closed(1)
	await settle()
	check(Navigation.current_route==closing_route,"closing does not forcibly replace current workbench page")
	check(WorkbenchSession.state.session.status=="finished","closing does not erase practice")
	print("WORKBENCH: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
