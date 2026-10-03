extends "res://tests/verify_workbench_drag.gd"

func _ready() -> void:
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	super._ready()

func motion(point: Vector2) -> void:
	var event:=InputEventMouseMotion.new()
	event.position=local_point(point)
	event.button_mask=MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(event,true)

func circle(center: Vector2) -> void:
	for i in range(1,33):
		motion(center+Vector2.from_angle(i*.24)*35)
		await get_tree().create_timer(.02).timeout

func actions(kind: String) -> int:
	var total:=0
	for action in WorkbenchSession.state.session.actions:
		if action.kind==kind: total+=1
	return total

func quiet() -> bool:
	for player in bench.sfx.loops.values():
		if player.playing: return false
	return true

func run() -> void:
	WorkbenchSession.reset_game()
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	check(quiet() and bench.sfx.trigger_count==0,"opening workbench does not play foley")
	for id in ["pour","stir","shake"]:
		var player: AudioStreamPlayer=bench.sfx.loops[id]
		check(player.bus==&"SFX" and player.stream.get_length()>.5 and player.stream.data.size()>1000,"real recorded clip on existing SFX bus: "+id)
	bench._act("cup",{"cup":"highball"})
	bench._issue("withdraw",{"material":"lime","ml":60,"vessel":"mixing"})
	bench._issue("withdraw",{"material":"gin","ml":60,"vessel":"mixing"})
	bench._act("ice",{"vessel":"mixing","ice":"cube"})
	var stock: Dictionary=WorkbenchSession.state.stock.duplicate(true)
	bench._show_category("器具")
	from_pantry("spoon","mixing")
	check(bench.data.spoon_vessel=="mixing" and bench.table.prop_visible("spoon"),"drop attaches spoon and release leaves it inside cup")
	check(WorkbenchSession.state.stock==stock,"attaching spoon does not consume ingredients")
	var attached: Dictionary=WorkbenchSession.snapshot()
	var receipt: Dictionary=attached.session.actions.back()
	check(WorkbenchSession.command(receipt.command_id,attached.session.id,receipt.kind,receipt.payload) and WorkbenchSession.state==attached,"retrying insertion does not create a second action")
	var save_path: String=Supplies.save_path
	Supplies.save_path=save_path+"/unwritable.json"
	check(not bench._issue("spoon",{"target":"glass"}) and WorkbenchSession.state==attached,"failed attachment save preserves spoon and cup together")
	Supplies.save_path=save_path
	WorkbenchSession.last_error=""
	var legacy: Dictionary=attached.session.duplicate(true)
	legacy.erase("spoon_vessel")
	check(WorkbenchSession._valid_session(legacy),"old sessions without spoon field remain compatible")
	var center: Vector2=bench.table.POS.mixing
	table_click(center)
	check(bench.data.spoon_vessel=="mixing","clicking cup does not accidentally retract spoon")
	var idle: Dictionary=bench.table.spoon_geometry()
	await capture("20-spoon-inserted")
	pointer(local_point(center+Vector2(35,0)),true)
	await circle(center)
	check(actions("stir")>0,"circular pointer motion records stirring")
	check(bench.sfx.loops.stir.playing and bench.table.stir_energy>.1,"motion drives liquid animation and stir recording")
	check(bench.table.spoon_geometry().tip.distance_to(idle.tip)>1,"spoon bowl moves inside the cup")
	var held_point: Vector2=bench.table.last_point
	var hover_event:=InputEventMouseMotion.new()
	hover_event.position=local_point(Vector2(40,15))
	hover_event.button_mask=0
	get_viewport().push_input(hover_event,true)
	check(bench.table.last_point==held_point and bench.table.dragging,"unpressed OS hover cannot interrupt held circular gesture")
	bench.table.set_process(false)
	await capture("21-spoon-stirring")
	bench.table.set_process(true)
	await get_tree().create_timer(.35).timeout
	check(not bench.sfx.loops.stir.playing,"stationary hold fades out stirring audio")
	pointer(local_point(center),false)
	check(bench.data.spoon_vessel=="mixing","release pauses without removing spoon")
	var handle: Vector2=bench.table.spoon_geometry().handle
	pointer(local_point(handle),true)
	await circle(handle)
	pointer(local_point(handle),false)
	check(bench.data.spoon_vessel=="mixing","holding and circling the handle does not trigger retract")
	await get_tree().create_timer(.3).timeout
	check(WorkbenchSession.load_state() and WorkbenchSession.state.session.spoon_vessel=="mixing","disk recovery preserves spoon attachment")
	Navigation.go_to(&"menu")
	await settle()
	Navigation.go_to(&"mixing")
	await settle()
	bench=home.active_page
	check(bench.table.prop_visible("spoon") and bench.sfx.trigger_count==0,"page round trip restores spoon without replaying sound")
	var hover:=InputEventMouseMotion.new()
	hover.position=local_point(bench.table.spoon_geometry().handle)
	get_viewport().push_input(hover,true)
	check(bench.table.hover=="spoon","pointer hovers handle before removal")
	table_click(bench.table.spoon_geometry().handle)
	check(bench.table.hover!="spoon","removal clears stale spoon hover without another mouse motion")
	check(bench.data.spoon_vessel=="" and not bench.table.prop_visible("spoon"),"one click on exposed handle retracts spoon")
	check(not bench.table.returning_spoon.is_empty(),"retraction animates spoon returning")
	await capture("22-spoon-stored")
	check(not bench._issue("stir",{"vessel":"mixing","seconds":.2}),"service rejects stirring with stored spoon")
	bench._show_category("器具")
	from_pantry("spoon","shaker")
	check(not bench._issue("lid"),"inserted spoon prevents closing shaker")
	table_click(bench.table.spoon_geometry().handle)
	bench._act("lid")
	check(not bench._issue("spoon",{"target":"shaker"}),"closed shaker refuses insertion")
	bench._act("lid")
	bench._issue("withdraw",{"material":"gin","ml":30,"vessel":"shaker"})
	bench._act("lid")
	center=bench.table.POS.shaker
	pointer(local_point(center),true)
	await get_tree().create_timer(.35).timeout
	check(not bench.sfx.loops.shake.playing,"holding shaker still is silent")
	for i in range(20):
		motion(center+Vector2(0,sin(i*.5)*65))
		await get_tree().create_timer(.02).timeout
	check(bench.sfx.loops.shake.playing,"front-back shake starts shaker recording")
	pointer(local_point(center),false)
	await get_tree().create_timer(.25).timeout
	check(quiet(),"releasing shaker stops all loops")
	bench._act("filter",{"source":"shaker","vessel":"glass","integrated_strainer":true})
	await get_tree().create_timer(.4).timeout
	check(bench.sfx.loops.pour.playing,"transfer sound follows visible pour stream")
	await get_tree().create_timer(.9).timeout
	check(quiet(),"completed transfer stops pouring sound")
	bench._show_category("基酒")
	from_pantry("gin","glass")
	await get_tree().create_timer(.45).timeout
	check(bench.sfx.loops.pour.playing,"bottle pouring starts recorded liquid audio")
	cancel()
	check(quiet(),"cancelled dose immediately stops audio")
	# Mute is a bus operation only: no settings file is written by this test.
	var bus:=AudioServer.get_bus_index(&"SFX")
	var was_muted:=AudioServer.is_bus_mute(bus)
	AudioServer.set_bus_mute(bus,true)
	bench.sfx.drive(.1,true,"",0)
	check(AudioServer.is_bus_mute(bus) and bench.sfx.loops.pour.bus==&"SFX","workbench respects existing SFX mute")
	AudioServer.set_bus_mute(bus,was_muted)
	bench.sfx._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	bench.sfx.drive(.1,true,"shake",1)
	check(quiet(),"focus loss silences and prevents audio restart")
	bench.sfx._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	bench.sfx.drive(.1,true,"",0)
	bench._open_storage("backpack")
	await settle()
	check(quiet(),"warehouse overlay silences workbench")
	bench.external_page.close_requested.emit()
	await settle()
	bench._show_category("器具")
	from_pantry("spoon","mixing")
	bench._act("filter",{"source":"mixing","vessel":"glass"})
	check(bench.data.spoon_vessel=="","pouring an attached vessel safely retracts its spoon")
	bench._issue("spoon",{"target":"glass"})
	for cup in WorkbenchSession.CUPS:
		bench._act("cup",{"cup":cup})
		await settle()
		var geometry: Dictionary=bench.table.spoon_geometry()
		check(bench.table._hit(geometry.handle)=="spoon" and geometry.handle.y<geometry.tip.y,"exposed handle remains reachable in cup: "+cup)
	bench._act("cup",{"cup":"highball"})
	bench._select("glass")
	center=bench.table.POS.glass
	pointer(local_point(center+Vector2(30,0)),true)
	await circle(center)
	check(bench.data.spoon_vessel=="glass" and bench.sfx.loops.stir.playing,"serving glass supports circular stirring without moving the cup")
	pointer(local_point(center),false)
	await capture("23-spoon-highball")
	table_click(bench.table.spoon_geometry().handle)
	check(bench.data.spoon_vessel=="","serving glass spoon also retracts on handle click")
	bench._issue("spoon",{"target":"glass"})
	bench._issue("finish")
	check(bench.data.spoon_vessel=="","serving removes spoon from completed cup")
	check(WorkbenchSession.state.stock.gin==stock.gin-30,"gestures audio transfer and cancelled pour never consume extra inventory")
	print("STIR AUDIO: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
