extends Control
signal close_requested
const Model := preload("res://scripts/stick_badminton_model.gd")
const Court := preload("res://scripts/stick_badminton_canvas.gd")
const FONT := preload("res://assets/fonts/NotoSerifSC.ttf")
const Rules := preload("res://scripts/stick_memory_rules.gd")
var surface: Control
var court: Control
var model: RefCounted
var overlay: Panel
var assist: CheckBox
var warmup: CheckBox
var previous_running := true
var left_held := false
var right_held := false
var accumulator := 0.0
var recorded := false
var playing := false
var result_status: Label
var paused := false
var jump_button: Button
var swing_button: Button
var pause_button: Button
var movement_buttons: Array[Button] = []
var reward_paper: Control
var hit_audio: AudioStreamPlayer
var point_audio: AudioStreamPlayer
var heard_hit := 0
var heard_point := 0
var match_context: Dictionary = {"mode": "practice", "visit_id": ""}
var touch_controls: Dictionary = {}
var key_flash := {"jump": 0.0, "swing": 0.0}

func _ready() -> void:
	# Internal demo: no story gates, reward writes or match-history persistence.
	previous_running = TimeManager.running
	TimeManager.set_running(false)
	surface = Control.new()
	add_child(surface)
	court = Court.new()
	court.size = Vector2(1600, 900)
	court.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(court)
	model = Model.new()
	model.begin("memory-preview")
	court.model = model
	court.practice_mode = match_context.get("mode") != "story"
	_button(surface, Rect2(1320, 65, 190, 56), "‹ 回到小线" if _story_match() else "‹ 返回手帐", _request_close)
	pause_button = _button(surface, Rect2(1105, 65, 190, 56), "暂停 · Esc", _pause)
	assist = CheckBox.new()
	assist.text = "自动跑位"
	assist.position = Vector2(1180, 130)
	assist.focus_mode = Control.FOCUS_NONE
	assist.add_theme_font_override("font", FONT)
	assist.add_theme_font_size_override("font_size", 22)
	assist.add_theme_color_override("font_color", Color("62472d"))
	_style_check(assist)
	surface.add_child(assist)
	var left := _button(surface, Rect2(122, 747, 160, 76), "←   A", func(): pass)
	left.button_down.connect(func(): left_held = true)
	left.button_up.connect(func(): left_held = false)
	var right := _button(surface, Rect2(296, 747, 160, 76), "D   →", func(): pass)
	right.button_down.connect(func(): right_held = true)
	right.button_up.connect(func(): right_held = false)
	movement_buttons = [left, right]
	jump_button = _button(surface, Rect2(1100, 747, 164, 76), "跳跃 · W", _jump)
	swing_button = _button(surface, Rect2(1278, 747, 200, 76), "挥拍 · 空格", _swing)
	_label(surface, Rect2(476, 754, 604, 59), "低球向上挑，高球上手击。\n太高跳起接，按左打短、右打深。", 20, true)
	_label(surface, Rect2(120, 839, 1360, 28), "先得 5 分获胜  ·  赢得《童年拾忆》  ·  酒馆时间暂停" if _story_match() else "内测演示 · 不发放剧情奖励 · 酒馆时间暂停", 18, true)
	_setup_audio()
	_intro()
	_sync_controls()
	resized.connect(_fit)
	_fit()

func _fit() -> void:
	var factor := minf(size.x / 1600, size.y / 900)
	surface.scale = Vector2.ONE * factor
	surface.position = (size - Vector2(1600, 900) * factor) * 0.5

func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("b28a54")
	style.set_border_width_all(2)
	style.set_corner_radius_all(7)
	style.shadow_color = Color(0.18, 0.10, 0.04, 0.20)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 3)
	return style

func _button(parent: Node, rect: Rect2, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.text = text
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color("f5e4c4"))
	button.add_theme_color_override("font_disabled_color", Color("b3a28a"))
	for entry in [["normal", "62462d"], ["hover", "967040"], ["pressed", "49331f"], ["disabled", "9b8870"]]: button.add_theme_stylebox_override(entry[0], _style(Color(entry[1])))
	button.set_meta("rest_style", button.get_theme_stylebox("normal"))
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _style_check(button: CheckBox) -> void:
	for state in ["normal", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["hover", "hover_pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("ead4ac")
		style.set_corner_radius_all(4)
		button.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, Color("62472d"))

func _label(parent: Node, rect: Rect2, text: String, px: int, centered: bool = false, color: Color = Color("62472d")) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", px)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _clear_overlay() -> void:
	if is_instance_valid(overlay):
		surface.remove_child(overlay)
		overlay.queue_free()
	overlay = null

func _panel() -> Panel:
	_clear_overlay()
	# The veil catches clicks outside the card, including the court buttons.
	overlay = Panel.new()
	overlay.size = Vector2(1600, 900)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var veil := StyleBoxFlat.new()
	veil.bg_color = Color(0.15, 0.10, 0.06, 0.48)
	overlay.add_theme_stylebox_override("panel", veil)
	surface.add_child(overlay)
	var panel := Panel.new()
	panel.position = Vector2(360, 210)
	panel.size = Vector2(880, 460)
	panel.add_theme_stylebox_override("panel", _style(Color("f4e5c9")))
	overlay.add_child(panel)
	return panel

func _intro() -> void:
	var p := _panel()
	_label(p, Rect2(42, 30, 795, 64), "另一支球拍，给你。" if _story_match() else "童年拾忆 · 内测演示", 34, true)
	_label(p, Rect2(60, 110, 760, 112), "小线把牛仔帽扶正，走到球网另一边。\n“都说了这么多以前的事了。陪我打一局？”" if _story_match() else "陪小线打一场五分友谊赛。\n当前为内测演示，不推进剧情、不发放奖励。", 25, true)
	_label(p, Rect2(58, 224, 766, 77), "空格击球：低球自动挑起，高球上手挥拍，太高跳起接。\n先得 5 分获胜；按左打短、右打深，自动跑位只帮你移动。", 21, true)
	warmup = CheckBox.new()
	warmup.text = "先试两个球，不记分"
	warmup.button_pressed = true
	warmup.position = Vector2(278, 309)
	warmup.focus_mode = Control.FOCUS_NONE
	warmup.add_theme_font_override("font", FONT)
	warmup.add_theme_font_size_override("font_size", 22)
	warmup.add_theme_color_override("font_color", Color("62472d"))
	_style_check(warmup)
	p.add_child(warmup)
	var start := _button(p, Rect2(282, 365, 318, 60), "开始游戏", _start)
	start.tooltip_text = "内测演示：暂时开放体验，不推进剧情、不发放奖励。"

func _start() -> void:
	var practice := 2 if is_instance_valid(warmup) and warmup.button_pressed else 0
	_clear_overlay()
	warmup = null
	model = Model.new()
	model.begin("memory-" + Crypto.new().generate_random_bytes(16).hex_encode(), practice)
	court.model = model
	court.trail.clear()
	recorded = false
	playing = true
	paused = false
	court.paused = false
	heard_hit = 0
	heard_point = 0
	accumulator = 0
	left_held = false
	right_held = false
	touch_controls.clear()
	key_flash = {"jump": 0.0, "swing": 0.0}
	_sync_controls()

func _pause() -> void:
	if not playing or paused: return
	paused = true
	court.paused = true
	left_held = false
	right_held = false
	touch_controls.clear()
	accumulator = 0
	var p := _panel()
	_label(p, Rect2(42, 35, 796, 64), "球先放一会儿。", 35, true)
	_label(p, Rect2(70, 128, 740, 80), "当前比分  %d : %d\n暂停期间，比赛和酒馆时间都停在这里。" % [model.player_score, model.ai_score], 25, true)
	_label(p, Rect2(70, 238, 740, 58), "继续这一球，或重新开始一场五分友谊赛。", 23, true)
	_button(p, Rect2(42, 365, 235, 60), "继续 · Esc", _resume)
	_button(p, Rect2(300, 365, 280, 60), "重新开一局", _start)
	_button(p, Rect2(605, 365, 235, 60), "回到小线" if _story_match() else "返回手帐", _close)
	_sync_controls()

func _resume() -> void:
	if not playing or not paused: return
	_clear_overlay()
	paused = false
	court.paused = false
	accumulator = 0
	_sync_controls()

func _jump() -> void:
	if playing and not paused:
		model.jump()
		key_flash.jump = 0.14
		_sync_controls()

func _swing() -> void:
	if playing and not paused:
		model.swing()
		key_flash.swing = 0.14
		_sync_controls()

func _lit_control(button: Button, lit: bool) -> void:
	button.add_theme_stylebox_override("normal", button.get_theme_stylebox("pressed") if lit else button.get_meta("rest_style"))

func _request_close() -> void:
	if playing: _pause()
	else: _close()

func _sync_controls() -> void:
	var active := playing and not paused
	if not active or model.phase not in ["ready", "rally"]:
		left_held = false
		right_held = false
	for button in movement_buttons: button.disabled = not active or model.phase not in ["ready", "rally"]
	jump_button.disabled = not active or model.phase != "rally"
	swing_button.disabled = not active or (model.phase != "rally" and not (model.phase == "ready" and model.server == 0))
	swing_button.text = "发球 · 空格" if model.phase == "ready" and model.server == 0 else "挥拍 · 空格"
	pause_button.disabled = not playing
	pause_button.text = "已暂停" if paused else "暂停 · Esc"
	assist.disabled = not active
	_lit_control(movement_buttons[0], active and (left_held or touch_controls.values().has("left") or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)))
	_lit_control(movement_buttons[1], active and (right_held or touch_controls.values().has("right") or Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)))
	_lit_control(jump_button, active and key_flash.jump > 0)
	_lit_control(swing_button, active and key_flash.swing > 0)

func _process(dt: float) -> void:
	if not is_instance_valid(court): return
	for key in key_flash: key_flash[key] = maxf(0, float(key_flash[key]) - dt)
	if not paused: court.elapsed += dt
	if playing and not paused:
		accumulator += minf(dt, 0.1)
		var move := float(right_held or touch_controls.values().has("right") or Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(left_held or touch_controls.values().has("left") or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		while accumulator >= 1.0 / 120 and model.phase != "finished":
			model.step(1.0 / 120, move, assist.button_pressed)
			accumulator -= 1.0 / 120
		_play_feedback()
		if model.phase == "finished":
			playing = false
			_result()
		elif model.phase == "rally":
			court.trail.append(model.shuttle)
			if court.trail.size() > 11: court.trail.pop_front()
		else: court.trail.clear()
	_sync_controls()
	court.queue_redraw()

func _record_result() -> bool:
	# Deliberately session-local. A demo win must not look like a story reward.
	recorded = Rules.valid_result(model.result())
	return recorded

func _story_match() -> bool:
	return match_context.get("mode") == "story"

func _result() -> void:
	playing = false
	paused = false
	court.paused = false
	left_held = false
	right_held = false
	var saved := _record_result()
	var won: bool = model.player_score >= Rules.TARGET
	var story := _story_match()
	var p := _panel()
	var title := "你赢了！" if won else "这一局，小线赢了。"
	if not story and won: title = "练习获胜！"
	_label(p, Rect2(42, 22, 796, 58), title, 35, true)
	_label(p, Rect2(100, 89, 680, 60), "%d : %d    最长 %d 拍" % [model.player_score, model.ai_score, model.longest_rally], 28, true)
	var response := "“先说好，这分得算啊。下回你可别说我记错了。”\n再来一局，把下一分接回来？"
	if won and story: response = "“行啊，最后这球接得好。回去坐会儿吧，我有样东西给你。”\n小线收起球拍，朝酒馆门口抬了抬头。"
	elif won: response = "这一局演示，你先拿到了五分。\n比赛结果仅本局展示，不发放剧情奖励。"
	_label(p, Rect2(60, 168, 760, 92), response, 24, true)
	var status := "比分记下了，下回接着打。" if saved else "比分还没记好，请再试一次。"
	if won and story: status = "回到酒馆，听听小线接下来想说的话。" if saved else "比赛结果还没记好，请再试一次。"
	elif not story and saved: status = "演示结束，比分不写入正式存档。"
	result_status = _label(p, Rect2(70, 276, 740, 50), status, 25, true)
	if won and story:
		_button(p, Rect2(250, 365, 380, 60), "回到酒馆，听小线说" if saved else "保存结果并回酒馆", _close)
	else:
		_button(p, Rect2(42, 365, 235, 60), "再打一局", _start)
		if not saved:
			_button(p, Rect2(300, 365, 280, 60), "保存比赛记录", func():
				result_status.text = "比赛记录已保存。" if _record_result() else "暂时没保存好，请稍后再试。"
			)
		_button(p, Rect2(605, 365, 235, 60), "回到小线" if story else "返回手帐", _close)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or is_instance_valid(reward_paper): return
	if _touch_input(event): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if paused: _resume()
			elif playing: _pause()
			else: _close()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode in [KEY_S, KEY_SPACE, KEY_DOWN]:
			if playing and not paused: _swing()
			elif not playing and is_instance_valid(warmup) and is_instance_valid(overlay): _start()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode in [KEY_W, KEY_UP] and playing and not paused:
			_jump()
			get_viewport().set_input_as_handled()

func _touch_input(event: InputEvent) -> bool:
	if not playing or paused: return false
	if event is InputEventScreenTouch:
		if not event.pressed:
			if not touch_controls.has(event.index): return false
			touch_controls.erase(event.index)
		else:
			var local: Vector2 = surface.get_global_transform_with_canvas().affine_inverse() * event.position
			var target := _touch_target(local)
			if target.is_empty(): return false
			touch_controls[event.index] = target
			if target == "jump": _jump()
			elif target == "swing": _swing()
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventScreenDrag and touch_controls.has(event.index):
		if touch_controls[event.index] in ["left", "right", "move_idle"]:
			var local: Vector2 = surface.get_global_transform_with_canvas().affine_inverse() * event.position
			var target := _touch_target(local)
			touch_controls[event.index] = target if target in ["left", "right"] else "move_idle"
		get_viewport().set_input_as_handled()
		return true
	# Screen touches above already act once; do not also fire their emulated mouse click.
	if event is InputEventMouseButton and event.device == -1:
		var local: Vector2 = surface.get_global_transform_with_canvas().affine_inverse() * event.position
		if not _touch_target(local).is_empty():
			get_viewport().set_input_as_handled()
			return true
	return false

func _touch_target(point: Vector2) -> String:
	for entry in [[movement_buttons[0], "left"], [movement_buttons[1], "right"], [jump_button, "jump"], [swing_button, "swing"]]:
		if not entry[0].disabled and Rect2(entry[0].position, entry[0].size).has_point(point): return str(entry[1])
	return ""

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		left_held = false
		right_held = false
		touch_controls.clear()
		if playing and not paused: _pause()

func _setup_audio() -> void:
	hit_audio = AudioStreamPlayer.new()
	hit_audio.bus = &"SFX"
	hit_audio.volume_db = -15
	hit_audio.stream = _soft_note(920, 0.07)
	add_child(hit_audio)
	point_audio = AudioStreamPlayer.new()
	point_audio.bus = &"SFX"
	point_audio.volume_db = -20
	point_audio.stream = _soft_note(520, 0.17)
	add_child(point_audio)

func _soft_note(frequency: float, duration: float) -> AudioStreamWAV:
	var samples := PackedByteArray()
	var rate := 22050
	var count := int(rate * duration)
	samples.resize(count * 2)
	for i in range(count):
		var t := float(i) / rate
		var envelope := sin(minf(1, t / 0.004) * PI / 2) * exp(-t * 42)
		var wave := sin(TAU * frequency * t) * 0.65 + sin(TAU * frequency * 2.7 * t) * 0.22
		samples.encode_s16(i * 2, int(wave * envelope * 18000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = samples
	return stream

func _play_feedback() -> void:
	if model.hit_serial != heard_hit:
		heard_hit = model.hit_serial
		hit_audio.pitch_scale = 1.12 if model.hit_quality == "跳击" else (1.0 if model.last_hitter == 0 else 0.86)
		hit_audio.play()
	if model.point_serial != heard_point:
		heard_point = model.point_serial
		point_audio.pitch_scale = 1.2 if model.point_winner == 0 else 0.84
		point_audio.play()

func can_close() -> bool:
	if _story_match() and model.phase == "finished" and not recorded:
		if not _record_result():
			if is_instance_valid(result_status): result_status.text = "比赛结果还没记好，请再试一次。"
			return false
	return true

func _close() -> void:
	if not can_close(): return
	if close_requested.get_connections().is_empty(): get_tree().change_scene_to_file("res://scenes/home.tscn")
	else: close_requested.emit()

func _exit_tree() -> void:
	TimeManager.set_running(previous_running)
