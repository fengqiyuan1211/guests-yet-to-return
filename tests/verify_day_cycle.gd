extends Node
var failures: Array[String] = []
var capture := false
var home: Control

func _ready() -> void:
	capture = "--screenshots" in OS.get_cmdline_user_args()
	get_tree().create_timer(45).timeout.connect(func(): push_error("Day-cycle test timeout"); get_tree().quit(2))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func settle() -> void:
	await get_tree().create_timer(0.25).timeout

func click(button: Control) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = button.get_global_rect().get_center()
	down.pressed = true
	get_viewport().push_input(down, true)
	var up := down.duplicate()
	up.pressed = false
	get_viewport().push_input(up, true)

func screenshot(name: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../output/day-cycle-preview")
	DirAccess.make_dir_recursive_absolute(folder)
	check(get_viewport().get_texture().get_image().save_png(folder.path_join(name)) == OK, "Screenshot save")

func test_clock() -> void:
	var clock = load("res://scripts/time_manager.gd").new()
	add_child(clock)
	clock.set_process(false)
	var events := {"open": 0, "close": 0}
	clock.business_opened.connect(func(_day): events.open += 1)
	clock.business_closed.connect(func(_day): events.close += 1)
	clock._process(0.4)
	check(clock.minutes_since_midnight == 1080, "Subsecond accumulation")
	clock._process(0.6)
	check(clock.minutes_since_midnight == 1081, "One second is exactly one minute")
	clock._process(2.5)
	check(clock.minutes_since_midnight == 1083, "Dropped frames preserve elapsed time")
	clock.set_running(false)
	clock._process(100.0)
	check(clock.minutes_since_midnight == 1083, "Pause freezes time")
	clock.set_running(true)
	clock._process(0.5)
	clock.advance_minutes(116)
	check(clock.is_open and events.open == 1 and clock.minutes_since_midnight == 1200, "20:00 opens once")
	check(not clock.start_early(), "Cannot skip while open")
	clock.advance_minutes(240)
	check(clock.day == 1 and clock.minutes_since_midnight == 0 and clock.is_open, "Midnight belongs to same business day")
	clock.advance_minutes(239)
	check(clock.is_open and events.close == 0, "03:59 stays open")
	clock.advance_minutes(1)
	check(not clock.is_open and clock.day == 2 and events.close == 1, "04:00 closes once and advances business day")
	check(clock.start_early() and not clock.start_early(), "Skip starts once, duplicate is rejected")
	clock._process(1.0)
	check(clock.fast_forwarding and clock.minutes_since_midnight > 240 and clock.minutes_since_midnight < 1200, "Skip visibly traverses daytime")
	clock._process(3.0)
	check(clock.minutes_since_midnight == 1200 and clock.is_open and not clock.fast_forwarding and events.open == 2, "Skip lands exactly at 20:00")
	clock._process(1.0)
	check(clock.minutes_since_midnight == 1201, "Normal rate resumes after skip")
	clock.advance_minutes(1440)
	check(events.open == 3 and events.close == 2 and clock.day == 3, "Large advance visits all shift boundaries")
	clock.queue_free()

func run() -> void:
	test_clock()
	TimeManager.set_process(false)
	var balance := SlotWallet.balance
	home = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	check(not home.service_started and home.get_node("%GuestLayer").get_child_count() == 0, "Preparation starts empty")
	await screenshot("01-dusk-preparation.png")
	click(home.get_node("%OpenButton"))
	check(TimeManager.fast_forwarding and home.get_node("%OpenButton").disabled, "Native button starts accelerated clock")
	TimeManager._process(2.0)
	await settle()
	await screenshot("02-clock-fast-forward.png")
	TimeManager._process(2.0)
	await settle()
	check(home.service_started and not home.guest_profile.is_empty(), "20:00 automatically welcomes a guest")
	check(not home.get_node("%OpenButton").disabled, "Service button enabled at opening")
	home.get_node("%GuestLayer").show_guest(1)
	TimeManager.advance_minutes(60)
	await settle()
	await screenshot("03-night-open.png")
	var background = home.get_node("Background")
	check(background.light_weights.y > 0.99, "Night painting is active")
	check(background.weights_at(18 * 60).is_zero_approx(), "Dusk has its own stable period")
	var last: Vector3 = background.weights_at(0.0)
	for minute in range(1, 1441):
		var weights: Vector3 = background.weights_at(float(minute))
		check(weights.x >= 0 and weights.y >= 0 and weights.z >= 0 and weights.x + weights.y + weights.z <= 1.0001, "Blend weights stay valid")
		check(weights.distance_to(last) < 0.025, "No abrupt time-of-day switch")
		last = weights
	check(background.weights_at(4.75 * 60).y > 0 and background.weights_at(4.75 * 60).z > 0, "Night-to-dawn blends both paintings")
	check(background.weights_at(7.25 * 60).x > 0 and background.weights_at(7.25 * 60).z > 0, "Dawn-to-day blends both paintings")
	Navigation.go_to(&"codex")
	await settle()
	TimeManager.advance_minutes(7 * 60)
	await settle()
	check(TimeManager.minutes_since_midnight == 240 and TimeManager.day == 2, "Integration crosses midnight to 04:00")
	check(home.service_started and home.closing_pending and not home.guest_profile.is_empty(), "04:00 preserves final reception")
	Navigation.go_to(&"home")
	home.on_drink_served()
	Navigation.go_to(&"codex")
	await settle()
	check(home.get_node("%GuestLayer").get_child_count() == 0, "No character left after closing")
	check(Navigation.current_route == &"codex", "Non-service browsing remains available")
	Navigation.go_to(&"home")
	await settle()
	check(home.get_node("%SceneTitle").visible and not home.get_node("%GuestPortrait").visible, "Journal round trip restores new closed state")
	check(home.get_node("%NoteTitle").text.contains("已结束"), "Closing summary visible")
	await screenshot("04-forced-close.png")
	TimeManager.advance_minutes(2 * 60)
	await settle()
	check(background.light_weights.z > 0.99, "Dawn uses its independent painting")
	await screenshot("05-dawn.png")
	TimeManager.advance_minutes(6 * 60)
	await settle()
	check(background.light_weights.x > 0.99 and background.light_weights.y < 0.01, "Day uses lamps-off painting")
	await screenshot("06-day-lamps-off.png")
	for route in [&"shop", &"research"]:
		Navigation.go_to(route)
		await settle()
		check(Navigation.current_route == route and is_instance_valid(home.active_page), "Daytime feature entry available")
	Navigation.go_to(&"home")
	await settle()
	click(home.get_node("%OpenButton"))
	TimeManager._process(2.0)
	await settle()
	check(TimeManager.minutes_since_midnight == 16 * 60, "Afternoon early-opening passes through afternoon")
	await screenshot("07-next-evening-fast-forward.png")
	TimeManager._process(2.0)
	await settle()
	check(TimeManager.day == 2 and home.service_started and home.guest_count == 1, "Second night starts with a fresh guest count")
	Navigation.go_to(&"mixing")
	await settle()
	TimeManager.advance_minutes(8 * 60)
	await settle()
	check(Navigation.current_route == &"mixing" and home.closing_pending, "04:00 preserves active workbench")
	home.on_drink_served()
	check(Navigation.current_route == &"home" and not home.service_started, "explicit send-off ends final reception")
	check(SlotWallet.balance == balance, "Time changes do not invent revenue or modify wallet")
	print("DAY CYCLE VERIFICATION: ", "PASS" if failures.is_empty() else "FAIL", " — exact rate, shift boundaries, midnight, skip, lamps-off day, dusk/night/dawn, forced closing, browsing, journal visibility")
	get_tree().quit(0 if failures.is_empty() else 1)
