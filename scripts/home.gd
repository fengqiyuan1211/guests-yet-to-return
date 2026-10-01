extends Control
## Home owns presentation only. Future modules enter via Navigation routes.
signal service_preview_started
const ENTRY_PREVIEW := preload("res://scenes/entry_preview.tscn")
const DESIGN_SIZE := Vector2(1600, 900)
var service_started := false
var active_page: Control
var previous_focus: Control
var guest_profile: Dictionary = {}
var dialogue_index := 0
var guest_count := 0
var journal_hidden_nodes: Dictionary = {}
var selected_navigation_style: StyleBox
var story_choices: HBoxContainer
var _restoring_reception := false

func _ready() -> void:
	Navigation.register_page(&"mixing", preload("res://scenes/workbench.tscn"))
	Navigation.register_page(&"slots", preload("res://scenes/slot_machine.tscn"))
	Navigation.register_page(&"codex", preload("res://scenes/codex.tscn"))
	Navigation.register_page(&"menu", preload("res://scenes/drink_menu.tscn"))
	Navigation.register_page(&"settings", preload("res://scenes/settings_menu.tscn"))
	_setup_settings_button()
	selected_navigation_style = %HomeButton.get_theme_stylebox("normal")
	SlotWallet.balance_changed.connect(_on_balance_changed)
	_on_balance_changed(SlotWallet.balance)
	resized.connect(_fit_layout)
	_fit_layout()
	for button in get_tree().get_nodes_in_group("route_buttons"):
		button.pressed.connect(Navigation.go_to.bind(StringName(button.get_meta("route"))))
	%OpenButton.pressed.connect(_on_open_pressed)
	%NextGuestButton.pressed.connect(_on_next_guest_pressed)
	%TalkButton.pressed.connect(_on_talk_pressed)
	_setup_story_choices()
	StoryDialogue.changed.connect(_render_dialogue)
	%GuestLayer.guest_spawned.connect(_on_guest_spawned)
	%NextGuestButton.hide()
	%TalkButton.hide()
	%GuestPortrait.hide()
	%HomeButton.pressed.connect(func(): Navigation.go_to(&"home"))
	Navigation.route_requested.connect(_on_route_requested)
	TimeManager.business_opened.connect(_on_business_opened)
	TimeManager.business_closed.connect(_on_business_closed)
	TimeManager.fast_forward_changed.connect(_on_fast_forward_changed)
	TimeManager.time_changed.connect(_on_time_changed)
	GameSession.bind_home(self)
	if TimeManager.is_open:
		_restoring_reception = not StoryDialogue.guest_id.is_empty()
		_on_business_opened(TimeManager.day)
		_restoring_reception = false
	else:
		_show_closed_state(false, 0)
	_on_time_changed(TimeManager.day, TimeManager.minutes_since_midnight)
	%OpenButton.grab_focus()
	GameSession.save_game()

func _setup_settings_button() -> void:
	var emblem: TextureRect = find_child("Emblem", true, false)
	var button := Button.new()
	button.name = "SettingsButton"
	button.position = emblem.position - Vector2(4, 4)
	button.size = emblem.size + Vector2(8, 8)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = "设置"
	for style in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	button.mouse_entered.connect(func(): emblem.modulate = Color(1.25, 1.15, 1.0))
	button.mouse_exited.connect(func(): emblem.modulate = Color.WHITE)
	button.pressed.connect(func(): Navigation.go_to(&"settings"))
	emblem.get_parent().add_child(button)

func _fit_layout() -> void:
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	%Stage.scale = Vector2.ONE * factor
	%Stage.position = (size - DESIGN_SIZE * factor) * 0.5

func _on_balance_changed(value: int) -> void:
	%GoldValue.text = str(value)

func _on_open_pressed() -> void:
	if TimeManager.fast_forwarding:
		return
	if service_started:
		Navigation.go_to(&"mixing")
		return
	TimeManager.start_early()

func _scene_visibility(node: CanvasItem, value: bool) -> void:
	# If the journal is open, update the remembered home state instead of revealing it.
	if journal_hidden_nodes.has(node):
		journal_hidden_nodes[node] = value
	else:
		node.visible = value

func _on_business_opened(_day: int) -> void:
	if service_started:
		return
	service_started = true
	guest_count = 0
	_scene_visibility(%SceneTitle, false)
	_scene_visibility(%SceneKicker, false)
	_scene_visibility(find_child("SceneRule", true, false), false)
	%NextGuestButton.show()
	%ActionCaption.hide()
	%OrderKicker.text = "今 晚 想 喝"
	var restored := false
	if _restoring_reception:
		guest_count = int(GameSession.visit.get("count", 1))
		%GuestLayer._bag.assign(GameSession.visit.get("bag", []))
		for i in range(%GuestLayer.profiles.size()):
			if %GuestLayer.profiles[i].id == StoryDialogue.guest_id:
				%GuestLayer.show_guest(i)
				restored = true
				break
	if not restored:
		_restoring_reception = false
		%GuestLayer.spawn_random_guest()
	_sync_service_controls()
	service_preview_started.emit()

func _on_business_closed(completed_day: int) -> void:
	_show_closed_state(true, completed_day)
	# Only an active service workbench ends with the shift. Daytime browsing stays open.
	if Navigation.current_route == &"mixing":
		Navigation.go_to(&"home")

func _show_closed_state(just_closed: bool, completed_day: int) -> void:
	var arrivals := guest_count
	StoryDialogue.end_guest()
	_clear_story_choices()
	%GuestTags.show()
	%OrderKicker.show()
	%NoteOrder.show()
	_layout_dialogue(false)
	service_started = false
	guest_profile = {}
	dialogue_index = 0
	%GuestLayer.clear_guest()
	%GuestPortrait.hide()
	%TalkButton.hide()
	%NextGuestButton.hide()
	%ActionCaption.show()
	%ActionCaption.text = "时钟快转至 20:00"
	%GuestName.text = "今日已歇业" if just_closed else "准备营业"
	%GuestRole.text = "04:00 收工 · 白天自由准备" if just_closed else "20:00 开门，等一位远道而来的客人"
	%GuestRole.tooltip_text = ""
	%GuestSpeech.text = "今晚到这里啦。白天可以购物、研发配方，也可以提前开始下一晚营业。" if just_closed else "还有时间备好材料、看看酒谱。准备好后，就让时针快转到今晚八点。"
	%GuestTags.text = "营业时间 20:00—04:00    /    现实 1 秒 = 游戏 1 分钟"
	%NoteTitle.text = "第 %d 夜已结束" % completed_day if just_closed else "营业准备"
	%NoteRole.text = "本夜共迎来 %d 位客人" % arrivals if just_closed else "白天备料，夜里迎客"
	%NoteBody.text = "客人已离店，酒馆暂时歇业。\n补好材料，再准备迎接下一晚。" if just_closed else "白天可以逛商店、研究新配方。\n夜幕降临后，再为来客调上一杯。"
	%OrderKicker.text = "营 业 时 间"
	%NoteOrder.text = "每晚 20:00 至次日 04:00"
	%SceneTitle.text = "白天备料，夜里迎客。"
	_scene_visibility(%SceneTitle, true)
	_scene_visibility(%SceneKicker, true)
	_scene_visibility(find_child("SceneRule", true, false), true)
	_sync_service_controls()
	_update_bottom_status()

func _on_fast_forward_changed(_active: bool) -> void:
	_sync_service_controls()

func _sync_service_controls() -> void:
	%OpenButton.disabled = TimeManager.fast_forwarding
	if TimeManager.fast_forwarding:
		%OpenButton.text = "时钟快转中…"
		%ShiftStatus.text = "快进至 20:00"
	elif service_started:
		%OpenButton.text = "前往调酒台    →"
		%ShiftStatus.text = "营业中 · 04:00 歇业"
	else:
		%OpenButton.text = "提前开始营业  →"
		%ShiftStatus.text = "备料中 · 20:00 开门"

func _on_next_guest_pressed() -> void:
	if service_started and Navigation.current_route == &"home":
		on_drink_served()

func _on_guest_spawned(profile: Dictionary) -> void:
	guest_profile = profile
	if not _restoring_reception:
		guest_count += 1
	dialogue_index = 0
	%GuestName.text = profile.name
	%GuestRole.text = profile.role
	%GuestPortrait.texture = %GuestLayer.portrait_texture(profile)
	%GuestPortrait.show()
	%TalkButton.show()
	%GuestRole.tooltip_text = profile.bio
	%NoteTitle.text = profile.name
	%NoteRole.text = profile.role
	%NoteBody.text = profile.bio
	if _restoring_reception:
		_render_dialogue()
	else:
		StoryDialogue.start_guest(str(profile.id))
	_update_bottom_status()

func _on_talk_pressed() -> void:
	if guest_profile.is_empty():
		return
	StoryDialogue.continue_talking()
	dialogue_index = StoryDialogue.idle_index

func _setup_story_choices() -> void:
	story_choices = HBoxContainer.new()
	story_choices.name = "StoryChoices"
	story_choices.position = Vector2(180, 184)
	story_choices.size = Vector2(802, 68)
	story_choices.add_theme_constant_override("separation", 12)
	find_child("GuestDialogue", true, false).add_child(story_choices)
	story_choices.hide()

func _clear_story_choices() -> void:
	if not is_instance_valid(story_choices):
		return
	for button in story_choices.get_children():
		story_choices.remove_child(button)
		button.queue_free()
	story_choices.hide()

func _layout_dialogue(telling_story: bool) -> void:
	var panel: Control = find_child("GuestDialogue", true, false)
	panel.position.y = 570 if telling_story else 618
	panel.size.y = 272 if telling_story else 224
	%GuestSpeech.position.y = 82 if telling_story else 86
	%GuestSpeech.size.y = 94 if telling_story else 90
	%GuestSpeech.add_theme_font_size_override("font_size", 22)
	%GuestSpeech.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	%GuestTags.position.y = 238 if telling_story else 181

func _render_dialogue() -> void:
	if guest_profile.is_empty() or StoryDialogue.guest_id != str(guest_profile.id):
		return
	var known := StoryDialogue.is_known(str(guest_profile.id))
	%GuestName.text = guest_profile.name if known else "？"
	%GuestRole.text = guest_profile.role if known else "？"
	%GuestRole.tooltip_text = guest_profile.bio if known else ""
	%NoteTitle.text = guest_profile.name if known else "？"
	%NoteRole.text = guest_profile.role if known else "？"
	%NoteBody.text = guest_profile.bio if known else "？"
	_clear_story_choices()
	_layout_dialogue(StoryDialogue.phase == "story")
	%GuestSpeech.text = StoryDialogue.speech
	%GuestTags.text = StoryDialogue.progress_label()
	%GuestTags.visible = not %GuestTags.text.is_empty()
	%OrderKicker.hide()
	%NoteOrder.text = ""
	%NoteOrder.hide()
	%TalkButton.show()
	%TalkButton.text = "再聊一句" if StoryDialogue.phase == "idle" else "接着听"
	if StoryDialogue.phase == "story":
		var node: Dictionary = StoryDialogue.episode.nodes[StoryDialogue.node_id]
		if node.has("transition"):
			%TalkButton.text = "先聊到这"
	var options := StoryDialogue.current_choices()
	if not options.is_empty():
		%TalkButton.hide()
		%GuestTags.hide()
		story_choices.show()
		var revision: int = StoryDialogue.revision
		for choice in options:
			var button := Button.new()
			button.text = choice.text
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.custom_minimum_size = Vector2(0, 68)
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.add_theme_font_size_override("font_size", 18)
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.focus_mode = Control.FOCUS_NONE
			for style in ["normal", "hover", "pressed"]:
				button.add_theme_stylebox_override(style, %TalkButton.get_theme_stylebox(style))
			button.pressed.connect(_choose_story.bind(str(choice.id), revision))
			story_choices.add_child(button)
	_update_bottom_status()

func _choose_story(choice_id: String, revision: int) -> void:
	StoryDialogue.choose(choice_id, revision)

func on_drink_served() -> void:
	# Public handoff for the future workbench; the current home send-off uses it too.
	if not service_started:
		return
	Navigation.go_to(&"home")
	if Navigation.current_route == &"home":
		%GuestLayer.spawn_random_guest()

func _update_bottom_status() -> void:
	if guest_profile.is_empty():
		%BottomStatus.text = "白天备料  /  %s  /  营业时间 20:00—04:00" % TimeManager.formatted_time()
	else:
		var display_name: String = guest_profile.name if StoryDialogue.is_known(str(guest_profile.id)) else "？"
		%BottomStatus.text = "营业中  /  %s  /  正在接待 %s" % [TimeManager.formatted_time(), display_name]

func _on_time_changed(day: int, minutes: int) -> void:
	%TimeValue.text = TimeManager.formatted_time()
	%DayValue.text = TimeManager.formatted_day()
	%TimeLabel.text = TimeManager.period_name()
	if not service_started:
		%SceneKicker.text = "%s  /  今晚 20:00 开门" % TimeManager.period_name()
	_update_bottom_status()

func _on_route_requested(route_id: StringName) -> void:
	if is_instance_valid(active_page) and active_page.has_method("can_close") and not active_page.can_close():
		return
	if is_instance_valid(active_page):
		active_page.queue_free()
		active_page = null
	# Restore exactly the home visibility that existed before entering the journal.
	for node in journal_hidden_nodes:
		if is_instance_valid(node):
			node.visible = journal_hidden_nodes[node]
	journal_hidden_nodes.clear()
	%GuestLayer.visible = route_id in [&"home", &"settings"]
	var codex_button: Button = find_child("CodexButton", true, false)
	%HomeButton.remove_theme_stylebox_override("normal")
	codex_button.remove_theme_stylebox_override("normal")
	var menu_button: Button = find_child("MenuButton", true, false)
	if menu_button != null:
		menu_button.remove_theme_stylebox_override("normal")
	if route_id == &"codex":
		codex_button.add_theme_stylebox_override("normal", selected_navigation_style)
	elif route_id == &"menu" and menu_button != null:
		menu_button.add_theme_stylebox_override("normal", selected_navigation_style)
	else:
		%HomeButton.add_theme_stylebox_override("normal", selected_navigation_style)
	if route_id == &"home":
		%HomeContent.visible = true
		if is_instance_valid(previous_focus) and previous_focus.is_inside_tree() and previous_focus.is_visible_in_tree():
			previous_focus.grab_focus()
		return
	previous_focus = get_viewport().gui_get_focus_owner()
	%HomeContent.visible = route_id in [&"slots", &"codex", &"menu", &"settings"]
	if route_id in [&"codex", &"menu"]:
		for node in %HomeContent.get_children():
			if node is CanvasItem and node.name not in ["TopBar", "Navigation", "Version"]:
				journal_hidden_nodes[node] = node.visible
				node.hide()
	if Navigation.registered_pages.has(route_id):
		active_page = Navigation.registered_pages[route_id].instantiate()
		%PageHost.add_child(active_page)
	else:
		active_page = ENTRY_PREVIEW.instantiate()
		%PageHost.add_child(active_page)
		active_page.configure(Navigation.ROUTES[route_id])
	if active_page.has_signal("close_requested"):
		active_page.connect("close_requested", func(): Navigation.go_to(&"home"))
	if active_page.has_signal("restart_completed"):
		active_page.connect("restart_completed", _on_game_restarted)
	active_page.modulate.a = 0.0
	create_tween().tween_property(active_page, "modulate:a", 1.0, 0.16)

func _on_game_restarted() -> void:
	Navigation.go_to(&"home")
	guest_count = 0
	%GuestLayer._bag.clear()
	%GuestLayer._last_id = ""
	_show_closed_state(false, 0)
	_on_time_changed(TimeManager.day, TimeManager.minutes_since_midnight)
	_on_balance_changed(SlotWallet.balance)
	GameSession.save_game()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and Navigation.current_route != &"home":
		Navigation.go_to(&"home")
		get_viewport().set_input_as_handled()
