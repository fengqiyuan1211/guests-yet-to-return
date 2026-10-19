extends "res://tests/verify_opening_visual_revision.gd"
var title_seen := false
var monitor_transition := false

func _process(_delta: float) -> void:
	if monitor_transition and is_instance_valid(get_tree().current_scene):
		if get_tree().current_scene.scene_file_path.ends_with("title_screen.tscn"): title_seen=true

func shot(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute("/tmp/opening-handoff")
	get_viewport().get_texture().get_image().save_png("/tmp/opening-handoff/"+label+".png")

func wait_action() -> void:
	while is_instance_valid(page) and page.busy: await get_tree().process_frame
	await settle()

func jump(id: String) -> void:
	check(OpeningFlow.update_departure({"node":id}),"prepare narrative checkpoint "+id)
	page._render()
	page.dialogue.visible_characters=-1
	page.clock=page.dialogue.text.length()
	await get_tree().create_timer(.45).timeout

func run() -> void:
	if not GameSession.save_path.begins_with("/tmp/"): get_tree().quit(2); return
	TimeManager.set_running(false)
	if "--handoff-resume" in OS.get_cmdline_user_args():
		check(OpeningFlow.arrival_pending() and TimeManager.is_open,"restart resumes interrupted arrival at opening hour")
		var visit_id: String=str(CustomerService.state.active.get("id",""))
		var guest_state:=StoryDialogue.session_snapshot()
		get_tree().current_scene=null
		check(OpeningFlow.enter_game(),"continue interrupted arrival")
		if OpeningTransition.busy: await OpeningTransition.finished
		var home: Control=get_tree().current_scene
		var press:=InputEventKey.new()
		press.keycode=KEY_SPACE; press.physical_keycode=KEY_SPACE; press.pressed=true
		Input.parse_input_event(press)
		await get_tree().create_timer(.5).timeout
		check(home.arrival_scene.fast_forward.active,"new entrance supports held Space fast-forward")
		check(Engine.time_scale==1.0 and not TimeManager.running,"entrance speed remains local, business stays paused")
		press=press.duplicate(); press.pressed=false; Input.parse_input_event(press)
		await settle()
		check(not home.arrival_scene.fast_forward.active,"release restores normal entrance speed")
		await home.arrival_scene.completed
		check(StoryDialogue.session_snapshot()==guest_state,"resumed arrival preserves dialogue cursor")
		check(str(CustomerService.state.active.get("id",""))==visit_id,"resumed arrival preserves customer visit")
		check(not OpeningFlow.arrival_pending() and TimeManager.running,"resumed arrival finishes exactly once")
		print("HANDOFF RESUME: %d checks, %d failures" % [count,failures.size()])
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	check(OpeningFlow.begin_story() and OpeningFlow.begin_tutorial() and OpeningFlow.finish_tutorial(true),"prepare private post-tutorial story")
	await show_scene("res://scenes/opening_departure.tscn")
	page.set_process(false)
	var stock: Dictionary=Supplies.inventory.serialize()
	var gold:=SlotWallet.balance
	await jump("sign_receipt")
	page._advance()
	check(page.busy and OpeningFlow.state.departure.signed,"sign commits before showing its feedback")
	page._advance()
	check(OpeningFlow.state.departure.node=="find_you","repeat signing cannot skip a beat")
	await get_tree().create_timer(.4).timeout
	shot("01-signed-receipt")
	await wait_action()
	await jump("give_water")
	page._advance()
	check(page.busy and OpeningFlow.state.departure.water,"water action locks input while moving")
	await wait_action()
	page.dialogue.visible_characters=-1
	await settle()
	shot("02-water-delivered")
	check(Supplies.inventory.serialize()==stock and SlotWallet.balance==gold,"story gestures do not change formal stock or money")
	for sku in ["sku_gin_london_dry","sku_tonic_water","sku_lime_wedge"]:
		check(Supplies.purchase(sku,1),"purchase real preparation "+sku)
	check(preload("res://scripts/opening_preparation.gd").publish("gin_and_tonic"),"publish one craftable opening drink")
	await jump("turn_sign")
	page._advance()
	page._advance()
	check(page.busy and OpeningFlow.state.departure.node=="my_door","double flip cannot finish the story")
	await get_tree().create_timer(.65).timeout
	shot("03-sign-open")
	await wait_action()
	page.dialogue.visible_characters=-1
	var economy: Dictionary=Supplies.inventory.serialize()
	gold=SlotWallet.balance
	get_tree().current_scene=null
	monitor_transition=true
	page._advance()
	check(OpeningTransition.busy,"finish uses persistent transition")
	check(not OpeningFlow.finish_opening(),"duplicate finish cannot initiate a second transition")
	# Global input, not just a manually invoked callback: hold through destination loading.
	var held:=InputEventKey.new()
	held.keycode=KEY_SPACE; held.physical_keycode=KEY_SPACE; held.pressed=true
	Input.parse_input_event(held)
	await get_tree().create_timer(1.8).timeout
	check(OpeningTransition.busy,"held Space keeps the next scene input-locked")
	check(not TimeManager.running and OpeningFlow.arrival_pending(),"clock stays paused while the handoff is locked")
	held=held.duplicate(); held.pressed=false; Input.parse_input_event(held)
	if OpeningTransition.busy: await OpeningTransition.finished
	var home: Control=get_tree().current_scene
	page.queue_free(); page=null
	check(home.scene_file_path.ends_with("home.tscn") and home.arrival_presenting,"transition goes directly to the saloon arrival")
	await get_tree().create_timer(.6).timeout
	shot("04-empty-saloon")
	while home.arrival_scene.phase!="arrival": await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	shot("05-first-guest")
	check(not TimeManager.running,"customer entrance does not consume business minutes")
	if "--handoff-interrupt" in OS.get_cmdline_user_args():
		check(GameSession.save_game() and OpeningFlow.arrival_pending(),"interrupted entrance keeps a durable resume marker")
		print("HANDOFF INTERRUPT: %d checks, %d failures" % [count,failures.size()])
		get_tree().quit(0 if failures.is_empty() else 1)
		return
	await home.arrival_scene.completed
	shot("06-business-ready")
	check(not title_seen,"normal completion never visits the title scene")
	check(TimeManager.running and not home.arrival_presenting and not OpeningFlow.arrival_pending(),"control and business time resume after the entrance")
	check(StoryDialogue.guest_id=="milo","first real guest is Milo")
	check(Supplies.inventory.serialize()==economy and SlotWallet.balance==gold,"handoff preserves purchased supplies and money")
	print("HANDOFF: %d checks, %d failures" % [count,failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
