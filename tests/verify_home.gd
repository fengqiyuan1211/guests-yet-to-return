extends Node
## Run: godot --path <project> res://tests/verify_home.tscn
## Add -- --screenshots for rendered verification artifacts.
var failures: Array[String] = []
var home: Control
var capture := false

func _ready() -> void:
	capture = "--screenshots" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func screenshot(file: String) -> void:
	if not capture:
		return
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../output/godot-home-preview")
	DirAccess.make_dir_recursive_absolute(folder)
	var result := get_viewport().get_texture().get_image().save_png(folder.path_join(file))
	check(result == OK, "Screenshot save failed")

func run() -> void:
	home = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	check(Navigation.current_route == &"home", "Initial route should be home")
	check(not home.service_started, "Opening the home must not start trading")
	check(home.get_node("%GuestLayer").get_child_count() == 0, "Home should begin without a fixed guest")
	var old_time := TimeManager.minutes_since_midnight
	TimeManager.advance_minutes(5)
	await settle()
	check(TimeManager.minutes_since_midnight != old_time, "Game clock must advance")
	check(home.get_node("%TimeValue").text == TimeManager.formatted_time(), "Clock label must follow game time")
	await screenshot("01-home.png")
	# Exercise native GUI hit testing, not only directly calling the handlers.
	var button: Button = home.find_child("ShopButton", true, false)
	var point := button.get_global_rect().get_center()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = point
	down.pressed = true
	get_viewport().push_input(down, true)
	var up := down.duplicate()
	up.pressed = false
	get_viewport().push_input(up, true)
	await settle()
	check(Navigation.current_route == &"shop", "Native click must open the shop entry")
	if is_instance_valid(home.active_page):
		check(home.active_page.get_node("%Tabs").get_child_count() == 5, "Shop needs five categories")
		home.active_page.get_node("%Tabs").get_child(2).pressed.emit()
		check(home.active_page.selected_tab == 2, "Shop category switching failed")
		await screenshot("02-shop-entry.png")
		# Blank paper catches input instead of accidentally closing via backdrop.
		var panel := home.active_page.get_node("Page") as Control
		check(panel.mouse_filter == Control.MOUSE_FILTER_STOP, "Entry panel must block backdrop click")
		home.active_page.get_node("%ReturnButton").pressed.emit()
	await settle()
	check(Navigation.current_route == &"home", "Return should restore home")
	for route in Navigation.ROUTES:
		Navigation.go_to(route)
		await settle()
		check(is_instance_valid(home.active_page), "Missing entry: %s" % route)
		var key := InputEventKey.new()
		key.keycode = KEY_ESCAPE
		key.pressed = true
		get_viewport().push_input(key, true)
		await settle()
		check(Navigation.current_route == &"home", "Escape did not return: %s" % route)
	home.get_node("%OpenButton").pressed.emit()
	await get_tree().create_timer(4.1).timeout
	check(home.service_started, "Start service preview failed")
	await screenshot("03-service-preview.png")
	home.get_node("%OpenButton").pressed.emit()
	check(Navigation.current_route == &"mixing", "Service action should route to mixing")
	Navigation.go_to(&"home")
	await settle()
	check(home.service_started, "Returning must preserve service preview state")
	# Validate fit at phone landscape and tablet aspect ratios.
	for dimensions in [Vector2(1920, 1080), Vector2(1280, 720), Vector2(1600, 720), Vector2(1024, 768)]:
		home.size = dimensions
		home._fit_layout()
		var stage := home.get_node("%Stage") as Control
		var extent := stage.position + stage.size * stage.scale
		check(stage.position.x >= -0.1 and stage.position.y >= -0.1, "Stage outside viewport")
		check(extent.x <= dimensions.x + 0.1 and extent.y <= dimensions.y + 0.1, "Stage clipped")
	print("HOME VERIFICATION: ", "PASS" if failures.is_empty() else "FAIL", " — navigation, categories, keyboard return, service state, responsive fit")
	get_tree().quit(0 if failures.is_empty() else 1)
