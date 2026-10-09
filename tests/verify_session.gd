extends Node
var failures: Array[String] = []
var home: Control
var mode := "seed"

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	TimeManager.set_process(false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--session-mode="):
			mode = arg.trim_prefix("--session-mode=")
	call_deferred("run")

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func click(button: Control) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = button.get_global_rect().get_center()
	down.pressed = true
	get_viewport().push_input(down, true)
	var up := down.duplicate()
	up.pressed = false
	get_viewport().push_input(up, true)

func capture(name: String) -> void:
	if not "--screenshots" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://../output/session-game-preview")
	DirAccess.make_dir_recursive_absolute(directory)
	check(get_viewport().get_texture().get_image().save_png(directory.path_join(name + ".png")) == OK, "Screenshot saved")

func run() -> void:
	if not GameSession.save_path.begins_with("/tmp/") or not StoryDialogue.save_path.begins_with("/tmp/") or not SlotWallet.save_path.begins_with("/tmp/"):
		get_tree().quit(2)
		return
	home = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	var guests = home.get_node("%GuestLayer")
	if mode == "seed":
		check(TimeManager.day == 1 and not home.service_started, "Fresh session")
		TimeManager.advance_minutes(120)
		for night in range(2):
			TimeManager.advance_minutes(480)
			home.on_drink_served()
			TimeManager.advance_minutes(960)
		TimeManager.advance_minutes(225)
		guests.show_guest(3)
		await settle()
		click(home.story_choices.get_child(0)) # Name reveal.
		await settle()
		click(home.get_node("%TalkButton"))
		await settle()
		click(home.story_choices.get_child(1)) # Stop on a selected branch reply.
		SlotWallet.balance = 777
		SlotWallet.spin_count = 12
		SlotWallet.hidden_misses = 12
		check(SlotWallet.persist(), "Wallet fixture saved")
		check(GameSession.save_game(), "Clock and active dialogue saved together")
		check(TimeManager.day == 3 and TimeManager.minutes_since_midnight == 1425, "Seed third day 23:45")
	elif mode == "resume":
		check(TimeManager.day == 3 and TimeManager.minutes_since_midnight == 1425, "Separate process restored day and minute")
		check(home.guest_profile.id == "stick" and StoryDialogue.guest_id == "stick", "Same guest restored")
		check(StoryDialogue.phase == "story" and StoryDialogue.node_id == "start_reply2", "Same selected branch restored")
		check(StoryDialogue.is_known("stick") and home.get_node("%GuestName").text == "小线", "Name knowledge retained")
		check(SlotWallet.balance == 777 and SlotWallet.hidden_misses == 12, "Wallet retained")
		var count: int = home.guest_count
		var history := StoryDialogue.history.duplicate(true)
		click(home.find_child("SettingsButton", true, false))
		await settle()
		check(Navigation.current_route == &"settings" and not TimeManager.running, "Emblem opens paused settings")
		TimeManager._process(8.0)
		check(TimeManager.minutes_since_midnight == 1425, "Settings freezes clock")
		await capture("01-settings")
		click(home.active_page.restart_button)
		await settle()
		check(home.active_page.confirming and SlotWallet.balance == 777 and TimeManager.day == 3, "First restart click does not reset anything")
		await capture("02-confirm-restart")
		click(home.active_page.continue_button)
		await settle()
		check(Navigation.current_route == &"home" and TimeManager.running, "Cancel resumes game")
		check(StoryDialogue.history == history and home.guest_count == count, "Cancel preserves reception exactly")
		var steps := 0
		while StoryDialogue.phase == "story" and steps < 20:
			steps += 1
			await settle()
			if not StoryDialogue.current_choices().is_empty():
				click(home.story_choices.get_child(0))
			else:
				click(home.get_node("%TalkButton"))
		check(StoryDialogue.phase == "idle" and int(StoryDialogue.progress.stick.completed) == 1, "Completed this visit only")
		click(home.get_node("%TalkButton"))
		check(GameSession.save_game(), "Idle session saved")
	elif mode == "idle_reset":
		check(StoryDialogue.guest_id == "stick" and StoryDialogue.phase == "idle" and int(StoryDialogue.progress.stick.completed) == 1, "Reload stays in idle, does not start chapter two")
		check(StoryDialogue.speech == StoryDialogue.smalltalk.stick[0], "Idle line retained")
		click(home.find_child("SettingsButton", true, false))
		await settle()
		click(home.active_page.restart_button)
		await settle()
		click(home.active_page.restart_button)
		await settle()
		check(Navigation.current_route == &"home" and not home.service_started, "Confirmed restart returns to preparation")
		check(TimeManager.day == 1 and TimeManager.minutes_since_midnight == 1080 and TimeManager.running, "Restart day/time")
		check(StoryDialogue.progress.is_empty() and StoryDialogue.phase == "none", "Restart clears stories and known identities")
		check(SlotWallet.balance == 300 and SlotWallet.hidden_misses == 0 and SlotWallet.spin_count == 0 and SlotWallet.hidden_prizes.is_empty(), "Restart clears wallet/pity/reward records")
		check(guests._bag.is_empty() and guests.get_child_count() == 0, "Restart clears active guests and queue")
		await capture("03-restarted")
	elif mode == "fresh_check":
		check(TimeManager.day == 1 and TimeManager.minutes_since_midnight == 1080 and StoryDialogue.progress.is_empty() and SlotWallet.balance == 300, "Restart persists across a new process")
		check(TimeManager.start_early(), "Begin fast forward")
		TimeManager._process(1.0)
		check(TimeManager.fast_forwarding and GameSession.save_game(), "Persist partial fast forward")
	elif mode == "fast_resume":
		check(TimeManager.fast_forwarding and not home.service_started, "Restore unfinished fast forward")
		TimeManager._process(3.0)
		check(TimeManager.minutes_since_midnight == 1200 and TimeManager.is_open and home.service_started and home.guest_count == 1, "Fast forward finishes once at opening")
		TimeManager.advance_minutes(480)
		check(TimeManager.day == 2 and home.closing_pending, "Closing after restore preserves last guest")
		home.on_drink_served()
		check(not home.service_started and StoryDialogue.phase=="none","send-off completes restored closing")
		check(GameSession.save_game(), "Closed state saved")
	elif mode == "closed_check":
		check(TimeManager.day == 2 and TimeManager.minutes_since_midnight == 240 and not home.service_started and StoryDialogue.phase == "none", "Reload at dawn remains closed on day two")
	elif mode == "legacy_check":
		check(TimeManager.day == 1 and TimeManager.minutes_since_midnight == 1080, "Legacy build had no saved clock")
		check(StoryDialogue.is_known("stick") and int(StoryDialogue.progress.stick.completed) == 1 and SlotWallet.balance == 777, "Upgrade keeps legacy stories and wallet")
	check(GameSession.last_error.is_empty(), "No session error")
	print("SESSION ", mode, ": ", "PASS" if failures.is_empty() else "FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)
