extends "res://tests/verify_opening.gd"
const Pixel=preload("res://scripts/pixel_art.gd")
const Composition=preload("res://scripts/saloon_composition.gd")

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await get_tree().create_timer(.8).timeout
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute("/tmp/opening-preview")
	get_viewport().get_texture().get_image().save_png("/tmp/opening-preview/"+label+".png")

func space_edge(down: bool, echo := false) -> void:
	var event:=InputEventKey.new()
	event.keycode=KEY_SPACE
	event.physical_keycode=KEY_SPACE
	event.pressed=down
	event.echo=echo
	get_viewport().push_input(event,true)

func run() -> void:
	if not GameSession.save_path.begins_with("/tmp/"): get_tree().quit(2); return
	TimeManager.set_running(false)
	var hold=preload("res://scripts/story_fast_forward.gd").new()
	hold.press()
	check(hold.step(.2,true)==1.0 and hold.release(),"short press remains a single tap")
	hold.press()
	check(hold.step(.36,true)==10.0,"hold activates exactly 10x after threshold")
	check(not hold.release() and hold.step(1,true)==1.0,"release restores 1x without extra advance")
	hold.press()
	check(hold.step(1,false)==1.0 and not hold.release(),"holding at an interactive beat cannot submit it on release")
	hold.press(); hold.step(.4,true); hold.cancel()
	check(not hold.release() and not hold.active,"focus/modal cancellation cannot create a delayed tap")
	var timer=preload("res://scripts/story_autoplay.gd").new()
	check(timer.tick(3,40,true,true,true),"hold advances completed prose even with autoplay off")
	check(not timer.enabled and not timer.tick(100,40,true,false,true),"hold never changes autoplay preference or bypasses interaction")
	var shared:=Pixel.texture("res://assets/art/saloon-day-unlit-v2.png")
	check(shared.resource_path==Composition.BACKGROUND_PATH,"story and main saloon share approved background")
	check(Pixel.texture("res://assets/workbench/background.png")==shared,"tutorial and normal workbench share approved background")
	check(Pixel.scene("saloon").atlas==shared,"saloon atlas route also shares the background")
	check(Pixel.scene("city-bar-faceless").atlas.resource_path.contains("two-men-story"),"memory uses revised two-men art")
	check(OpeningFlow.begin_story(),"begin isolated story")
	OpeningFlow.advance(OpeningFlow.node_index("s02_00"))
	await show_scene("res://scenes/opening_story.tscn")
	page.set_process(false)
	page.dialogue.visible_characters=page.dialogue.text.length()
	await capture("revision-01-two-men")
	var index:=int(OpeningFlow.state.node)
	await key_press(KEY_SPACE)
	check(OpeningFlow.state.node==index+1,"real Space tap advances exactly once on release")
	index=int(OpeningFlow.state.node)
	if DisplayServer.get_name()!="headless":
		get_window().grab_focus(); await settle()
	space_edge(true); space_edge(true,true)
	check(OpeningFlow.state.node==index,"key down and OS repeat do not skip prose")
	page.fast_forward.step(.4,true)
	if DisplayServer.get_name()!="headless":
		page.type_clock=0.0; page.dialogue.visible_characters=0
		page._process(.1)
		check(page.dialogue.visible_characters==page.dialogue.text.length(),"held key reveals the whole line without waiting for typewriting")
		check(page.speed_hint.visible and page.background.playback_speed==10.0,"hold feedback and CG motion use 10x")
		await capture("revision-02-fast-forward")
		# Desktop focus may move while a screenshot awaits rendering. Re-arm explicitly
		# after focus loss, as a real player must, before checking uninterrupted holds.
		if not get_window().has_focus() or not page.fast_forward.held:
			get_window().grab_focus(); await settle()
			space_edge(true); page.fast_forward.step(.4,true)
		page.dialogue.visible_characters=page.dialogue.text.length()
		page._process(2.1)
		check(int(OpeningFlow.state.node)==index+1 and page.fast_forward.held,"sustained hold automatically continues prose without re-pressing")
		index=int(OpeningFlow.state.node)
		for i in range(4): page._process(.17)
		check(int(OpeningFlow.state.node)==index+4 and page.fast_forward.held,"one hold flows across four more lines without typing pauses")
		index=int(OpeningFlow.state.node)
	space_edge(false)
	check(not page.fast_forward.active and OpeningFlow.state.node==index,"long release never advances an extra line")
	check(page.background.playback_speed==1.0 and not page.speed_hint.visible,"release immediately clears speed and hint")
	for id in ["s04_05","s01_04"]:
		OpeningFlow.advance(OpeningFlow.node_index(id)); page._render()
		index=int(OpeningFlow.state.node)
		space_edge(true); page.fast_forward.step(1,page._can_auto_advance()); space_edge(false)
		check(OpeningFlow.state.node==index and not is_instance_valid(page.mail_reader),"hold cannot choose or open mail: "+id)
	page._open_history(); space_edge(true); space_edge(false)
	check(not page.fast_forward.held and is_instance_valid(page.history_panel),"history consumes Space without arming hold")
	page._close_history()
	OpeningFlow.advance(page.nodes.size()-1); page._render()
	space_edge(true); page.fast_forward.step(2,page._can_auto_advance()); space_edge(false)
	check(OpeningFlow.state.phase=="cg","holding at tutorial gate cannot start gameplay")
	page.dialogue.visible_characters=page.dialogue.text.length()
	await capture("revision-05-island-saloon")
	page.queue_free(); await settle(); page=null
	check(OpeningFlow.begin_tutorial(),"prepare isolated tutorial")
	await show_scene("res://scenes/workbench.tscn")
	await capture("revision-04-workbench")
	check(OpeningFlow.finish_tutorial(true),"prepare isolated departure")
	OpeningFlow.state.tutorial_status="completed"
	OpeningFlow.state.tutorial={"session":{"result":{"cup":"coupe","capacity_ml":160,"contents":{"contents":{"sku_bleu_de_minuit":90.0}},"evaluation":{"score":90}}}}
	await show_scene("res://scenes/opening_departure.tscn")
	page.set_process(false)
	var cup=page.props.get_child(0)
	var foot: float=cup.position.y+cup.size.y-48
	check(cup.tabletop_shadow and foot>Composition.COUNTER_Y+30 and foot<640,"cocktail foot and contact shadow land on tabletop above dialogue")
	check(cup.size.x<=240 and page.background.texture==shared,"cocktail reduced and departure background unified")
	page.dialogue.visible_characters=page.dialogue.text.length()
	await capture("revision-03-cocktail-on-runner")
	var departure_id: String=OpeningFlow.state.departure.node
	await key_press(KEY_SPACE)
	check(OpeningFlow.state.departure.node!=departure_id,"departure still accepts short Space taps")
	if DisplayServer.get_name()!="headless":
		get_window().grab_focus(); await settle()
	space_edge(true); page.fast_forward.step(.4,true)
	if DisplayServer.get_name()!="headless":
		page.clock=0.0; page.dialogue.visible_characters=0; page._process(.1)
		check(page.dialogue.visible_characters==page.dialogue.text.length(),"departure hold reveals whole line immediately")
		var before_run: int=page.current_index()
		for i in range(3): page._process(.17)
		check(page.current_index()==before_run+3 and page.fast_forward.held,"departure hold survives ordinary lines and room changes")
	space_edge(false)
	for id in ["sign_receipt","give_water","turn_sign","my_door"]:
		OpeningFlow.update_departure({"node":id}); page._render()
		space_edge(true); page.fast_forward.step(2,page._can_auto_advance()); space_edge(false)
		check(OpeningFlow.state.departure.node==id and not OpeningFlow.state.departure.opened,"hold stops at departure action: "+id)
	OpeningFlow.update_departure({"node":"today"}); page._render()
	page.dialogue.visible_characters=page.dialogue.text.length()
	await key_press(KEY_SPACE)
	check(page.busy,"ordinary cross-room transition begins")
	space_edge(true)
	check(page.fast_forward.held,"Space pressed during a dissolve arms continuous fast-forward")
	page.fast_forward.step(.3,true); page._process(.01)
	check(page.fast_forward.active,"room dissolve can also accelerate during a hold")
	space_edge(false)
	check(not page.fast_forward.held,"release during room dissolve is never lost")
	while page.busy: await get_tree().process_frame
	check(not page.fast_forward.active,"room dissolve cannot leave fast-forward stuck on")
	check(Engine.time_scale==1.0 and not TimeManager.running,"CG speed never accelerates economy or global time")
	page.queue_free(); await settle(); page=null
	print("OPENING VISUAL/HOLD: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
