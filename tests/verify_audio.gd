extends Node
var failures: Array[String] = []
var home: Control
var mode := "exercise"

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func finish_fade() -> void:
	if is_instance_valid(SaloonAudio.fade) and SaloonAudio.fade.is_running():
		SaloonAudio.fade.custom_step(4.0)

func _ready() -> void:
	for path in [SaloonAudio.settings_path, GameSession.save_path, StoryDialogue.save_path, SlotWallet.save_path, MenuCatalog.save_path]:
		if not path.begins_with("/tmp/"):
			get_tree().quit(2)
			return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--audio-test-mode="):
			mode = arg.trim_prefix("--audio-test-mode=")
	TimeManager.set_process(false)
	call_deferred("run")

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://../output/audio-preview")
	DirAccess.make_dir_recursive_absolute(directory)
	check(get_viewport().get_texture().get_image().save_png(directory.path_join(name + ".png")) == OK, "Screenshot saved")

func click_at(control: Control, fraction: float) -> void:
	var rect := control.get_global_rect()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = rect.position + Vector2(rect.size.x * fraction, rect.size.y * 0.5)
	event.pressed = true
	get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event, true)

func run() -> void:
	home = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	check(SaloonAudio.players.size() == 2, "Only two persistent music decks")
	for path in SaloonAudio.DAY_TRACKS + SaloonAudio.NIGHT_TRACKS:
		var stream := SaloonAudio._stream_for(path)
		check(stream != null and stream.get_length() > 60.0, "Real music imported: " + path)
	if mode == "resume":
		check(TimeManager.minutes_since_midnight == 1200 and SaloonAudio.active_path == SaloonAudio.NIGHT_TRACK, "Startup picks the jazz half of the nighttime playlist")
		check(SaloonAudio.get_volume("Master") == 63 and SaloonAudio.get_volume("Music") == 0 and SaloonAudio.get_volume("SFX") == 41, "Preferences survive a separate process")
		check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Saved zero really mutes music")
	else:
		check(SaloonAudio.active_path in SaloonAudio.DAY_TRACKS, "Daytime starts with daytime music")
		finish_fade()
		SaloonAudio.players[SaloonAudio.active_index].seek(SaloonAudio.players[SaloonAudio.active_index].stream.get_length() - 1.0)
		var prior := SaloonAudio.active_path
		await get_tree().create_timer(0.08).timeout
		SaloonAudio._process(0.0)
		check(SaloonAudio.active_path != prior and SaloonAudio.active_path in SaloonAudio.DAY_TRACKS, "Daytime rotates before track ends")
		finish_fade()
		TimeManager.restore({"minutes": 1199})
		TimeManager.advance_minutes(1)
		SaloonAudio._process(0.0)
		check(SaloonAudio.active_path == SaloonAudio.NIGHT_TRACK, "20:00 opens with the nighttime jazz")
		check(SaloonAudio.players[0].playing and SaloonAudio.players[1].playing, "Day-night transition overlaps both tracks")
		finish_fade()
		var night_player := SaloonAudio.players[SaloonAudio.active_index]
		TimeManager.restore({"minutes": 0})
		SaloonAudio._process(0.0)
		check(SaloonAudio.players[SaloonAudio.active_index] == night_player, "Midnight does not restart music")
		Navigation.go_to(&"shop")
		await settle()
		Navigation.go_to(&"home")
		await settle()
		check(night_player.playing and SaloonAudio.players[SaloonAudio.active_index] == night_player, "Navigation preserves the current player")
		Navigation.go_to(&"settings")
		await settle()
		var settings: Control = home.active_page
		check(not TimeManager.running and night_player.playing, "Settings pauses clock, music keeps playing")
		await capture("01-volume-settings")
		click_at(settings.volume_sliders.Music, 0.3)
		check(SaloonAudio.get_volume("Music") > 20 and SaloonAudio.get_volume("Music") < 40, "Slider accepts actual pointer input through scaled UI")
		settings.volume_sliders.Music.value = 0
		check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Slider zero is silence")
		settings.volume_sliders.Music.value = 72
		check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "Raising slider unmutes immediately")
		settings.volume_sliders.Master.value = 63
		settings.volume_sliders.SFX.value = 41
		get_window().size = Vector2i(960, 540)
		await settle()
		await capture("02-volume-small-window")
		check(settings.get_node("Page").get_global_rect().encloses(settings.audio_controls.get_global_rect()), "Sliders remain inside parchment")
		settings._ask_restart()
		await settle()
		check(settings.confirming and not settings.audio_controls.visible, "Restart confirmation has no overlapping sliders")
		await capture("03-restart-confirmation")
		settings._ask_restart()
		await settle()
		SaloonAudio._process(0.0)
		check(TimeManager.day == 1 and SaloonAudio.active_path in SaloonAudio.DAY_TRACKS, "Restart switches back to daytime music")
		check(SaloonAudio.get_volume("Master") == 63 and SaloonAudio.get_volume("SFX") == 41, "Restart preserves audio preferences")
		finish_fade()
		TimeManager.restore({"minutes": 239})
		SaloonAudio._process(0.0)
		TimeManager.advance_minutes(1)
		SaloonAudio._process(0.0)
		check(SaloonAudio.active_path in SaloonAudio.DAY_TRACKS, "04:00 close switches to daytime, including fast fade reversal")
		finish_fade()
		var audible_count := 0
		for player in SaloonAudio.players:
			if player.playing:
				audible_count += 1
		check(audible_count == 1, "Outgoing deck stops after fade")
		var sfx: Node = load("res://scripts/slot_audio.gd").new()
		add_child(sfx)
		for player in sfx.players:
			check(player.bus == &"SFX", "Slot effects obey SFX volume")
		sfx.play_sound("coin")
		sfx.queue_free()
		SaloonAudio.set_volume("Music", 0)
		check(SaloonAudio.save_settings(), "Preferences saved")
		TimeManager.restore({"minutes": 1200})
		check(GameSession.save_game(), "Nighttime resume fixture saved")
	print("AUDIO ", mode, ": ", "PASS" if failures.is_empty() else failures)
	# Give the audio thread time to release playback handles before ending the test.
	SaloonAudio.set_process(false)
	if is_instance_valid(SaloonAudio.fade):
		SaloonAudio.fade.kill()
	for player in SaloonAudio.players:
		player.stop()
		player.stream = null
	SaloonAudio._streams.clear()
	await get_tree().create_timer(0.3).timeout
	get_tree().call_deferred("quit", 0 if failures.is_empty() else 1)
