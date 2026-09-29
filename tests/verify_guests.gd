extends Node
var failures: Array[String] = []
var home: Control
var capture := false
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
func _ready() -> void:
	capture = "--screenshots" in OS.get_cmdline_user_args()
	call_deferred("run")
func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
func click(control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = control.get_global_rect().get_center()
	event.pressed = true
	get_viewport().push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	get_viewport().push_input(event, true)
func screenshot(file: String) -> void:
	if not capture or DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../output/guest-game-preview")
	DirAccess.make_dir_recursive_absolute(folder)
	check(get_viewport().get_texture().get_image().save_png(folder.path_join(file)) == OK, "Screenshot save")
func run() -> void:
	if not SlotWallet.save_path.begins_with("/tmp/") or not StoryDialogue.save_path.begins_with("/tmp/"):
		get_tree().quit(1)
		return
	var balance := SlotWallet.balance
	home = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	var guests = home.get_node("%GuestLayer")
	check(guests.get_child_count() == 0 and home.guest_profile.is_empty(), "No guest before opening")
	check(guests.profiles.size() == 5, "Five profiles")
	await screenshot("00-before-opening.png")
	click(home.get_node("%OpenButton"))
	await get_tree().create_timer(4.1).timeout
	await settle()
	check(home.service_started and not home.guest_profile.is_empty(), "Native open button spawns guest")
	var seen: Array[String] = [home.guest_profile.id]
	var previous: String = home.guest_profile.id
	for i in range(1, 50):
		click(home.get_node("%NextGuestButton"))
		await settle()
		var current: String = home.guest_profile.id
		check(current != previous, "No adjacent repeat across bags")
		check(not seen.has(current), "Every bag has five distinct guests")
		seen.append(current)
		if seen.size() == 5:
			seen.clear()
		previous = current
	for i in range(5):
		home.guest_count = i
		guests.show_guest(i)
		await settle()
		var profile: Dictionary = home.guest_profile
		check(home.get_node("%GuestName").text == "？", "First encounter keeps name hidden")
		click(home.story_choices.get_child(0))
		await settle()
		if profile.id != "yellow_creature":
			click(home.get_node("%TalkButton"))
		else:
			guests.show_guest(i)
		await settle()
		check(home.get_node("%GuestName").text == profile.name, "Name sync")
		check(home.get_node("%GuestRole").tooltip_text == profile.bio, "Guest biography remains available")
		var guest_window: Control = guests.get_node("GuestWindow")
		check(guest_window.position.y + guest_window.size.y <= 600.0, "Guest stays behind counter edge")
		var dialogue: Control = home.find_child("GuestDialogue", true, false)
		var rail: Control = home.get_node("Stage/HomeContent/Navigation")
		check(is_equal_approx(dialogue.position.y + dialogue.size.y, rail.position.y + rail.size.y), "Dialogue bottom aligns with sidebar")
		check(dialogue.size.y >= 220.0, "Dialogue has generous height")
		check(home.get_node("%NoteBody").text == profile.bio, "Guest note updates with profile")
		check(home.get_node("%GuestSpeech").text == StoryDialogue.speech, "Authored dialogue sync")
		check(home.story_choices.get_child_count() == StoryDialogue.current_choices().size(), "Response options visible")
		check(home.get_node("%GuestPortrait").texture != null, "Portrait exists")
		check(home.get_node("%GuestSpeech").get_line_count() <= 3, "Dialogue fits three lines")
		await screenshot("%02d-%s.png" % [i + 1, profile.id])
		click(home.story_choices.get_child(0))
		check(home.get_node("%GuestSpeech").text == StoryDialogue.speech, "Choice updates line")
		var line: String = home.get_node("%GuestSpeech").text
		Navigation.go_to(&"shop")
		await settle()
		check(not guests.visible, "Guest hidden on feature page")
		Navigation.go_to(&"home")
		await settle()
		check(guests.visible and home.guest_profile.id == profile.id and home.get_node("%GuestSpeech").text == line, "Returning keeps guest and dialogue")
		click(home.get_node("%SlotsButton"))
		await settle()
		check(Navigation.current_route == &"slots", "Slots still accessible with guests")
		home.active_page.request_close()
		await settle()
		check(guests.visible and home.guest_profile.id == profile.id, "Slots return keeps guest")
	get_window().size = Vector2i(1280,576)
	await settle()
	await screenshot("06-phone-landscape.png")
	click(home.get_node("%TalkButton"))
	check(home.get_node("%GuestSpeech").text == StoryDialogue.speech, "Talk works at phone size")
	get_window().size = Vector2i(1024,768)
	await settle()
	await screenshot("07-tablet.png")
	check(SlotWallet.balance == balance, "Guest preview must not charge or award coins")
	guests.clear_guest()
	check(guests.get_child_count() == 0, "Guest removal leaves only original background")
	print("GUEST VERIFICATION: ", "PASS" if failures.is_empty() else "FAIL", " | five guests, shuffle bags, native clicks, story choices, portraits, route preservation, responsive screenshots")
	get_tree().quit(0 if failures.is_empty() else 1)
