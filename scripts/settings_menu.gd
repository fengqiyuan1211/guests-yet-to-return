extends Control
signal close_requested
signal restart_completed
var confirming := false
var was_running := true
var continue_button: Button
var restart_button: Button
var memory_button: Button
var audio_controls: VBoxContainer
var volume_sliders: Dictionary = {}

func _ready() -> void:
	was_running = TimeManager.running
	TimeManager.set_running(false)
	GameSession.save_game()
	%ReturnButton.hide()
	%FeatureList.hide()
	$Page/PreviewLabel.hide()
	$Page/Divider.hide()
	$Page.position.y = 115
	$Page.size.y = 670
	$Page/Eyebrow.text = "THE WESTERN SALOON  /  酒馆小憩"
	%CloseButton.pressed.connect(_resume)
	%Backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_cancel_or_resume()
	)
	continue_button = _button("继续游戏", _resume)
	restart_button = _button("重新开始", _ask_restart)
	memory_button = _button("童年球场 · 练习", _launch_memory)
	_build_audio_controls()
	_show_menu()

func _build_audio_controls() -> void:
	audio_controls = VBoxContainer.new()
	audio_controls.name = "AudioControls"
	audio_controls.position = Vector2(46, 204)
	audio_controls.size = Vector2(816, 264)
	audio_controls.add_theme_constant_override("separation", 12)
	$Page.add_child(audio_controls)
	var heading := Label.new()
	heading.text = "酒馆里的声音"
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", Color("654528"))
	audio_controls.add_child(heading)
	for entry in [["Master", "总音量"], ["Music", "背景音乐"], ["SFX", "音效"]]:
		var bus_name: String = entry[0]
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 60
		row.add_theme_constant_override("separation", 24)
		audio_controls.add_child(row)
		var label := Label.new()
		label.text = entry[1]
		label.custom_minimum_size.x = 132
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color("654528"))
		row.add_child(label)
		var slider := HSlider.new()
		slider.name = bus_name + "Volume"
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.value = SaloonAudio.get_volume(bus_name)
		slider.custom_minimum_size = Vector2(320, 54)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slider.tooltip_text = entry[1]
		_style_slider(slider)
		row.add_child(slider)
		volume_sliders[bus_name] = slider
		var amount := Label.new()
		amount.custom_minimum_size.x = 80
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		amount.add_theme_font_size_override("font_size", 21)
		amount.add_theme_color_override("font_color", Color("654528"))
		amount.text = "静音" if slider.value == 0 else "%d%%" % int(slider.value)
		row.add_child(amount)
		slider.value_changed.connect(func(value: float):
			SaloonAudio.set_volume(bus_name, value)
			amount.text = "静音" if value == 0 else "%d%%" % int(value)
		)

	var credit:=RichTextLabel.new()
	credit.custom_minimum_size=Vector2(816,48)
	credit.bbcode_enabled=true
	credit.fit_content=true
	credit.add_theme_font_size_override("normal_font_size",15)
	credit.add_theme_color_override("default_color",Color("654528"))
	credit.text='音乐：Kevin MacLeod (incompetech.com) · [url=https://creativecommons.org/licenses/by/4.0/]CC BY 4.0[/url]\n调酒台：[url=https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1300035]George Street Shuffle[/url]\n商店：[url=https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1600023]Carpe Diem[/url] · 研发：[url=https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1700069]Bossa Antigua[/url]'
	credit.meta_clicked.connect(func(url): OS.shell_open(str(url)))
	audio_controls.add_child(credit)

func _style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("bba17a")
	track.border_color = Color("967345")
	track.set_border_width_all(1)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	slider.add_theme_stylebox_override("slider", track)
	var filled := track.duplicate() as StyleBoxFlat
	filled.bg_color = Color("927044")
	slider.add_theme_stylebox_override("grabber_area", filled)
	var highlighted := filled.duplicate() as StyleBoxFlat
	highlighted.bg_color = Color("a67b3f")
	slider.add_theme_stylebox_override("grabber_area_highlight", highlighted)
	for key in ["grabber", "grabber_highlight"]:
		var fill := "#c49b58" if key == "grabber" else "#e0bb76"
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="30" height="30"><circle cx="15" cy="15" r="12" fill="%s" stroke="#74512d" stroke-width="2"/><circle cx="15" cy="15" r="7" fill="none" stroke="#f0d5a0"/><path d="M15 10v10" stroke="#74512d" stroke-width="2"/></svg>' % fill
		var image := Image.new()
		image.load_svg_from_string(svg)
		slider.add_theme_icon_override(key, ImageTexture.create_from_image(image))

func _button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 60)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for style in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(style, %ReturnButton.get_theme_stylebox(style))
	button.pressed.connect(action)
	%Tabs.add_child(button)
	return button

func _show_menu() -> void:
	confirming = false
	memory_button.show()
	audio_controls.show()
	%Tabs.position.y = 538
	%Description.position.y = 612
	%Description.size.y = 42
	%PageTitle.text = "设置"
	%PageSubtitle.text = "歇一会儿，再继续今晚的故事。"
	%Description.text = "关掉游戏后，下次仍会从这里继续。"
	if not GameSession.last_error.is_empty():
		%Description.text = GameSession.last_error
	continue_button.text = "继续游戏"
	restart_button.text = "重新开始"

func _ask_restart() -> void:
	if confirming:
		if GameSession.restart_game():
			was_running = true
			restart_completed.emit()
		else:
			%Description.text = GameSession.last_error
		return
	confirming = true
	memory_button.hide()
	audio_controls.hide()
	%Tabs.position.y = 440
	%Description.position.y = 250
	%Description.size.y = 132
	%PageTitle.text = "重新开始？"
	%PageSubtitle.text = "确定要从第一天重新开店吗？"
	%Description.text = "将回到第 1 天傍晚，金币恢复为 300。\n人物相识、故事进度、老虎机保底和奖励记录都会重置。"
	continue_button.text = "取消，继续游戏"
	restart_button.text = "确认重新开始"

func _launch_memory() -> void:
	if confirming or GameSession.resetting: return
	Navigation.memory_match_context = {"mode":"practice", "visit_id":""}
	Navigation.memory_resume_running = was_running
	was_running = false # This retiring settings page must not unpause the new match.
	Navigation.go_to(&"stick_badminton")

func _resume() -> void:
	if GameSession.resetting:
		return
	close_requested.emit()

func _cancel_or_resume() -> void:
	if GameSession.resetting:
		return
	if confirming:
		_show_menu()
	else:
		_resume()

func can_close() -> bool:
	return not GameSession.resetting

func _exit_tree() -> void:
	SaloonAudio.save_settings()
	TimeManager.set_running(was_running)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_cancel_or_resume()
		get_viewport().set_input_as_handled()
