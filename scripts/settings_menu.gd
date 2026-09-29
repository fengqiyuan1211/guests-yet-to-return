extends Control
signal close_requested
signal restart_completed
var confirming := false
var was_running := true
var continue_button: Button
var restart_button: Button

func _ready() -> void:
	was_running = TimeManager.running
	TimeManager.set_running(false)
	GameSession.save_game()
	%ReturnButton.hide()
	%FeatureList.hide()
	$Page/PreviewLabel.hide()
	$Page/Divider.hide()
	$Page.position.y = 220
	$Page.size.y = 460
	$Page/Eyebrow.text = "THE WESTERN SALOON  /  酒馆小憩"
	%CloseButton.pressed.connect(_resume)
	%Backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_cancel_or_resume()
	)
	continue_button = _button("继续游戏", _resume)
	restart_button = _button("重新开始", _ask_restart)
	_show_menu()

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
	%PageTitle.text = "重新开始？"
	%PageSubtitle.text = "确定要从第一天重新开店吗？"
	%Description.text = "将回到第 1 天傍晚，金币恢复为 300。\n人物相识、故事进度、老虎机保底和奖励记录都会重置。"
	continue_button.text = "取消，继续游戏"
	restart_button.text = "确认重新开始"

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
	TimeManager.set_running(was_running)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_cancel_or_resume()
		get_viewport().set_input_as_handled()
