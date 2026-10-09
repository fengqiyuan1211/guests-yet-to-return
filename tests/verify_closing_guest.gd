extends "res://tests/verify_research.gd"
func _ready() -> void:
	if OS.get_cmdline_user_args().has("--closing-resume"):
		if not Supplies.save_path.begins_with("/tmp/"): get_tree().quit(2); return
		TimeManager.set_process(false)
		call_deferred("resume_closing")
	else: super._ready()
func run() -> void:
	WorkbenchSession.reset_game()
	CustomerService.endpoint=""
	MenuCatalog.unlock_recipe("gin_and_tonic")
	MenuCatalog.save_menu([{"id":"gin_and_tonic","price":40}],MenuCatalog.design)
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	TimeManager.advance_minutes(1200-TimeManager.minutes_since_midnight)
	await settle()
	finish_story()
	Navigation.go_to(&"drink_selection")
	await settle()
	bench=home.active_page
	click(bench.start_button)
	await settle()
	check(Navigation.current_route==&"mixing","begin actual guest order")
	op("withdraw",{"material":"soda","ml":50,"vessel":"glass"})
	var before:=WorkbenchSession.snapshot()
	var guest_id: String=StoryDialogue.guest_id
	var visit_id: String=home.reception_id
	TimeManager.advance_minutes(481)
	await settle()
	check(TimeManager.minutes_since_midnight==240 and TimeManager.closing_pending,"4am pauses at boundary even on a long frame")
	check(home.closing_pending and home.service_started and TimeManager.closing_pending,"closing stops arrivals but keeps service")
	check(StoryDialogue.guest_id==guest_id and home.reception_id==visit_id,"closing keeps same guest and visit")
	check(Navigation.current_route==&"mixing" and WorkbenchSession.snapshot()==before,"closing neither dismisses bench nor loses unfinished cup")
	check(GuestService.serving_now(),"last guest may still receive a drink")
	check(GameSession.save_game(),"closing state is saved")
	var expected:=FileAccess.open(Supplies.save_path+".closing-expected",FileAccess.WRITE)
	expected.store_string(JSON.stringify({"session":WorkbenchSession.state.session,"guest":guest_id,"visit":visit_id}))
	expected.close()
	print("CLOSING GUEST: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)
func resume_closing() -> void:
	serial=100
	CustomerService.endpoint=""
	var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Supplies.save_path+".closing-expected"))
	home=load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	check(home.closing_pending and TimeManager.closing_pending,"restart restores closing pause")
	check(home.reception_id==expected.visit and StoryDialogue.guest_id==expected.guest,"restart restores last guest identity")
	check(same(WorkbenchSession.state.session,expected.session),"restart restores half cup and frozen order")
	Navigation.go_to(&"mixing")
	await settle()
	op("withdraw",{"material":"soda","ml":10,"vessel":"glass"})
	op("finish")
	check(GuestService.deliver(WorkbenchSession.state.session.result.drink_id),"can complete and deliver after scheduled closing")
	check(home.closing_pending,"evaluation does not immediately send guest away")
	for i in range(8):
		await settle()
		var record:=CustomerService.current_record()
		if record.is_empty() or record.feedback.done: break
		CustomerService.choose_feedback(0,int(record.feedback.round))
	finish_story()
	home.on_drink_served()
	await settle()
	check(not home.closing_pending and not home.service_started and StoryDialogue.guest_id.is_empty(),"send-off closes without spawning new guest")
	check(TimeManager.running and Navigation.current_route==&"home","time resumes after final send-off")
	print("CLOSING RESTORE: %d checks, %d failures" % [count,failures.size()])
	home.queue_free()
	await settle()
	get_tree().quit(0 if failures.is_empty() else 1)

func finish_story() -> void:
	for i in range(100):
		if StoryDialogue.phase!="story": break
		if StoryDialogue.current_choices().is_empty(): StoryDialogue.continue_talking()
		else: StoryDialogue.choose(StoryDialogue.current_choices()[0].id,StoryDialogue.revision)
