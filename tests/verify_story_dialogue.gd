extends Node
var failures: Array[String] = []
var home: Control
var paths := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

func click(control: Control) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.position = control.get_global_rect().get_center()
	down.pressed = true
	get_viewport().push_input(down, true)
	var up := down.duplicate()
	up.pressed = false
	get_viewport().push_input(up, true)

func capture(name: String) -> void:
	if not "--screenshots" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../output/story-game-preview")
	DirAccess.make_dir_recursive_absolute(folder)
	check(get_viewport().get_texture().get_image().save_png(folder.path_join(name + ".png")) == OK, "Capture " + name)

func walk(chapter: Dictionary, key: String, trail: Array) -> void:
	check(chapter.nodes.has(key) and not trail.has(key), "Valid acyclic node: " + chapter.id + "/" + key)
	if not chapter.nodes.has(key) or trail.has(key):
		return
	var node: Dictionary = chapter.nodes[key]
	var visited := trail.duplicate()
	visited.append(key)
	if node.has("transition"):
		check(node.transition == "resume_existing_dialogue_loop", "Every path hands back to chat")
		paths += 1
	elif node.has("choices"):
		for choice in node.choices:
			walk(chapter, choice.next, visited)
	elif node.has("next"):
		walk(chapter, node.next, visited)
	else:
		check(false, "Dead end: " + chapter.id + "/" + key)

func run() -> void:
	if not StoryDialogue.save_path.begins_with("/tmp/") or not SlotWallet.save_path.begins_with("/tmp/"):
		push_error("Use isolated /tmp saves for verification")
		get_tree().quit(2)
		return
	TimeManager.set_process(false)
	var balance := SlotWallet.balance
	home = load("res://scenes/home.tscn").instantiate()
	add_child(home)
	await settle()
	TimeManager.advance_minutes(120)
	var guests = home.get_node("%GuestLayer")
	check(home.service_started, "Open starts reception")
	for chapters in StoryDialogue.catalog.values():
		for chapter in chapters:
			walk(chapter, chapter.entry, [])
	check(paths == 161, "All 161 authored paths terminate")
	StoryDialogue.progress = {}
	for i in range(guests.profiles.size()):
		var id: String = guests.profiles[i].id
		var count := 1 if id == "yellow_creature" else 5
		for visit in range(count):
			guests.show_guest(i)
			await settle()
			if visit == 0:
				check(not StoryDialogue.is_known(id), "First encounter is unknown: " + id)
				check(home.get_node("%NoteTitle").text == "？" and home.get_node("%NoteBody").text == "？" and home.get_node("%GuestName").text == "？", "Identity is hidden before introduction")
				check(home.get_node("%GuestRole").tooltip_text.is_empty() and not home.get_node("%BottomStatus").text.contains(guests.profiles[i].name), "Tooltip and status cannot reveal name")
				StoryDialogue.load_progress()
				guests.show_guest(i)
				check(not StoryDialogue.is_known(id), "Reload before introduction keeps unknown state")
			else:
				check(StoryDialogue.is_known(id), "Later visits remember identity")
			check(int(StoryDialogue.episode.episode) == visit + 1, "Next visit advances one chapter: " + id)
			var chapter: Dictionary = StoryDialogue.episode
			var steps := 0
			while StoryDialogue.phase == "story" and steps < 20:
				steps += 1
				await settle()
				check(home.get_node("%GuestSpeech").text == StoryDialogue.speech, "Visible guest line matches node")
				var options := StoryDialogue.current_choices()
				if not options.is_empty():
					check(home.story_choices.get_child_count() == options.size(), "Native option count")
					var old_revision := StoryDialogue.revision
					var chosen: Dictionary = options[visit % options.size()]
					if visit == 0 and steps == 1:
						await capture(id + "-first-visit")
					click(home.story_choices.get_child(visit % options.size()))
					check(not StoryDialogue.choose(chosen.id, old_revision), "A stale click cannot choose twice")
					check(StoryDialogue.node_id == chosen.next, "Choice follows its own reply")
					if visit == 0 and steps == 1:
						check(StoryDialogue.is_known(id) and home.get_node("%GuestName").text == guests.profiles[i].name and home.get_node("%NoteBody").text == guests.profiles[i].bio, "Introduction reveals identity and biography")
						await settle()
						var note: Label = home.get_node("%NoteBody")
						check(note.get_line_count() * note.get_line_height() <= 91, "Revealed biography fits note: " + id)
						await capture(id + "-introduced")
				else:
					click(home.get_node("%TalkButton"))
			check(StoryDialogue.phase == "idle", "Story returns to idle chat")
			check(home.guest_profile.id == id and guests.get_child_count() == 1, "Story completion keeps guest")
			check(StoryDialogue.last_error.is_empty(), "Progress saved successfully")
			check(StoryDialogue.is_known(id), "Identity stays known after story")
			if id != "yellow_creature":
				check(int(StoryDialogue.progress[id].completed) == visit + 1, "Only acknowledged ending completes chapter")
				var heard: Dictionary = StoryDialogue.progress[id].heard.duplicate(true)
				click(home.get_node("%TalkButton"))
				await settle()
				var line: String = StoryDialogue.speech
				for j in range(StoryDialogue.smalltalk[id].size()):
					click(home.get_node("%TalkButton"))
				check(StoryDialogue.speech == line and StoryDialogue.progress[id].heard == heard, "Idle repeats without advancing story")
				if i == 0 and visit == 0:
					await capture("idle-chat")
			else:
				click(home.get_node("%TalkButton"))
				await settle()
				check(StoryDialogue.speech == "我是奶龙" and home.story_choices.get_child(0).text == "我才是奶龙", "Yellow creature repeats only its fixed gag")
		if id != "yellow_creature":
			guests.show_guest(i)
			check(StoryDialogue.phase == "idle", "After five visits no sixth chapter")
	# Unfinished choice/reply survives a new process-style reload and route changes.
	StoryDialogue.load_progress()
	for id in ["milo", "ada", "hank", "stick"]:
		check(int(StoryDialogue.progress[id].completed) == 5, "All five chapters persisted independently: " + id)
	StoryDialogue.progress = {}
	guests.show_guest(0)
	await settle()
	click(home.story_choices.get_child(0))
	await settle()
	click(home.get_node("%TalkButton"))
	await settle()
	click(home.story_choices.get_child(1))
	var pending: Dictionary = JSON.parse_string(JSON.stringify(StoryDialogue.progress))
	var saved_node := StoryDialogue.node_id
	var saved_speech := StoryDialogue.speech
	var saved_history := StoryDialogue.history.duplicate(true)
	StoryDialogue.load_progress()
	check(StoryDialogue.progress == pending, "File reload keeps progress for all guests")
	guests.show_guest(0)
	check(StoryDialogue.node_id == saved_node and StoryDialogue.history == saved_history, "Resume exact reply without duplicate history")
	for route in [&"shop", &"codex"]:
		Navigation.go_to(route)
		await settle()
		Navigation.go_to(&"home")
		await settle()
		check(StoryDialogue.speech == saved_speech and StoryDialogue.node_id == saved_node, "Page round trip keeps conversation")
	TimeManager.advance_minutes(480)
	check(home.closing_pending and StoryDialogue.node_id==saved_node,"04:00 preserves unfinished conversation")
	home.on_drink_served()
	check(StoryDialogue.phase == "none" and home.guest_profile.is_empty(), "send-off closes final reception")
	StoryDialogue.load_progress()
	check(StoryDialogue.progress == pending, "Closing preserves unfinished chapter")
	TimeManager.advance_minutes(960)
	guests.show_guest(0)
	check(StoryDialogue.node_id == saved_node and StoryDialogue.history == saved_history, "Next night resumes unfinished reply")
	Navigation.go_to(&"mixing")
	home.on_drink_served()
	check(Navigation.current_route == &"home" and home.guest_profile.id != guests.profiles[0].id, "Workbench handoff welcomes next guest")
	# Check every authored node's rendered geometry, including branches not chosen above.
	for i in range(guests.profiles.size()):
		guests.show_guest(i)
		for chapter in StoryDialogue.catalog[guests.profiles[i].id]:
			StoryDialogue.episode = chapter
			StoryDialogue.phase = "story"
			for key in chapter.nodes:
				if not chapter.nodes[key].has("text"):
					continue
				StoryDialogue._show_node(key)
				await settle()
				var label: Label = home.get_node("%GuestSpeech")
				check(label.get_line_count() * label.get_line_height() <= 94, "Text fits reserved space: " + chapter.id + "/" + key)
				check(label.position.y + label.size.y <= home.story_choices.position.y, "Speech stays above choices")
				check(home.story_choices.size.x <= 802 and home.story_choices.size.y <= 68, "Choices stay in dialogue panel")
	StoryDialogue.progress = {}
	guests.show_guest(3)
	await settle()
	get_window().size = Vector2i(1280, 576)
	await settle()
	await capture("phone-landscape")
	click(home.story_choices.get_child(0))
	check(StoryDialogue.current_choices().is_empty(), "Native options work at phone size")
	get_window().size = Vector2i(1024, 768)
	await settle()
	await capture("tablet")
	check(SlotWallet.balance == balance, "Story never modifies wallet")
	print("STORY DIALOGUE: ", "PASS" if failures.is_empty() else "FAIL", " | 161 paths, 21 visits, unknown identity/reveal, native choices, reload/resume, idle, closing, handoff, all-node text bounds")
	get_tree().quit(0 if failures.is_empty() else 1)
