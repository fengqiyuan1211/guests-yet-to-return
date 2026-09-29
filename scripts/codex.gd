extends Control
## Presentation-only journal. Blank mounting spaces are not unlocked/locked recipes.
signal close_requested
signal page_turned(page: int)

const PAGE_COUNT := 3
const PAGE_SIZE := Vector2(1280, 704)
const PAGE_ORIGIN := Vector2(284, 136)
const INK := Color("493019")
const TURN_SECONDS := 0.82
const INK_BUTTON_SCRIPT := preload("res://scripts/journal_ink_button.gd")
const CARD_SCRIPT := preload("res://scripts/journal_card.gd")
const BINDING_SCRIPT := preload("res://scripts/journal_binding.gd")
const TURN_SHADER := preload("res://assets/codex/page_turn.gdshader")

var page_index := 0
var selected_filter := 0
var turning := false
var page_content: Control
var previous_button: Button
var next_button: Button
var tabs: Array[Button] = []
var curl: TextureRect
var snapshot: SubViewport
var turn_tween: Tween
var paper: Texture2D
var press_position := Vector2.ZERO
var press_active := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper = load("res://assets/codex/journal-paper-v1.png")
	_build_frame()
	page_content = _make_page(page_index)
	page_content.position = PAGE_ORIGIN
	add_child(page_content)
	# The turning leaf is captured in its own viewport; no screen readback is needed.
	snapshot = SubViewport.new()
	snapshot.size = Vector2i(PAGE_SIZE)
	snapshot.transparent_bg = true
	snapshot.gui_disable_input = true
	snapshot.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(snapshot)
	curl = TextureRect.new()
	curl.name = "TurningLeaf"
	curl.position = PAGE_ORIGIN
	curl.size = PAGE_SIZE
	curl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	curl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	curl.texture = snapshot.get_texture()
	var material_instance := ShaderMaterial.new()
	material_instance.shader = TURN_SHADER
	material_instance.set_shader_parameter("paper_texture", paper)
	curl.material = material_instance
	curl.hide()
	add_child(curl)
	_build_controls()
	var binding := Control.new()
	binding.set_script(BINDING_SCRIPT)
	binding.position = Vector2(249, 136)
	binding.size = Vector2(80, 704)
	add_child(binding)
	_update_controls()
	next_button.grab_focus()

func _style(fill: Color, border: Color, thickness := 1) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(thickness)
	result.set_corner_radius_all(3)
	result.set_content_margin_all(4)
	return result

func _panel(parent: Node, rect: Rect2, style: StyleBoxFlat) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _label(parent: Node, rect: Rect2, text_value: String, font_size: int, color := INK, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.position = rect.position
	label.size = rect.size
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = alignment
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _build_frame() -> void:
	var leather := _style(Color("372316"), Color("9b6b38"), 2)
	leather.shadow_color = Color(0, 0, 0, 0.5)
	leather.shadow_size = 12
	leather.shadow_offset = Vector2(0, 7)
	_panel(self, Rect2(242, 123, 1334, 732), leather)
	_panel(self, Rect2(252, 132, 1314, 711), _style(Color("52301b"), Color("aa7743")))
	for inset in [8, 5, 2]:
		_panel(self, Rect2(PAGE_ORIGIN + Vector2(inset, inset), PAGE_SIZE), _style(Color("bd955b"), Color("714c2a")))

func _make_page(index: int) -> Control:
	var sheet := Control.new()
	sheet.name = "JournalPage"
	sheet.size = PAGE_SIZE
	sheet.theme = theme
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := TextureRect.new()
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.texture = paper
	texture.size = PAGE_SIZE
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(texture)
	_label(sheet, Rect2(180, 15, 330, 61), "酒 馆 图 鉴", 38)
	_label(sheet, Rect2(510, 32, 504, 31), "S A L O O N  R E C I P E  J O U R N A L", 16)
	_label(sheet, Rect2(1030, 27, 166, 34), "已点亮  0", 22)
	for i in range(6):
		var card := Control.new()
		card.set_script(CARD_SCRIPT)
		card.name = "EmptyCard%d" % i
		card.position = Vector2(148 + (i % 3) * 328, 144 + (i / 3) * 246)
		card.size = Vector2(300, 230)
		sheet.add_child(card)
		_label(card, Rect2(22, 12, 80, 28), "%03d" % (index * 6 + i + 1), 16, Color("8b6a45"))
	_label(sheet, Rect2(170, 638, 550, 36), "好酒的故事，等你写下。", 18, Color("795731"))
	_label(sheet, Rect2(66, 230, 40, 290), "酒\n谱\n手\n记", 20, Color("947345"), HORIZONTAL_ALIGNMENT_CENTER)
	_label(sheet, Rect2(948, 638, 220, 36), "—  %02d / %02d  —" % [index + 1, PAGE_COUNT], 19, Color("795731"), HORIZONTAL_ALIGNMENT_CENTER)
	return sheet

func _button(rect: Rect2, text_value: String) -> Button:
	var button := Button.new()
	button.set_script(INK_BUTTON_SCRIPT)
	button.position = rect.position
	button.size = rect.size
	button.text = text_value
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 23)
	# All surfaces are empty. Only text and a small pen underline respond to input.
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color("795b39"))
	button.add_theme_color_override("font_hover_color", Color("422915"))
	button.add_theme_color_override("font_pressed_color", Color("422915"))
	button.add_theme_color_override("font_focus_color", Color("422915"))
	button.add_theme_color_override("font_disabled_color", Color(0.40, 0.28, 0.17, 0.20))
	add_child(button)
	return button

func _build_controls() -> void:
	for i in range(3):
		var tab := _button(Rect2(PAGE_ORIGIN + Vector2(430 + i * 146, 88), Vector2(134, 44)), ["全部", "已点亮", "未点亮"][i])
		tab.name = "Filter%d" % i
		tab.pressed.connect(_select_filter.bind(i))
		tabs.append(tab)
	previous_button = _button(Rect2(PAGE_ORIGIN + Vector2(18, 144), Vector2(116, 482)), "‹")
	previous_button.set("is_margin", true)
	previous_button.add_theme_font_size_override("font_size", 36)
	previous_button.name = "PreviousPage"
	previous_button.tooltip_text = "上一页 · ←"
	previous_button.pressed.connect(turn_page.bind(-1))
	next_button = _button(Rect2(PAGE_ORIGIN + Vector2(1120, 144), Vector2(144, 482)), "›")
	next_button.set("is_margin", true)
	next_button.add_theme_font_size_override("font_size", 36)
	next_button.name = "NextPage"
	next_button.tooltip_text = "下一页 · →"
	next_button.pressed.connect(turn_page.bind(1))
	_label(self, Rect2(260, 860, 650, 28), "尚未收录酒款  /  轻点纸张两侧，或左右滑动翻页", 15, Color("d2b789"))

func _select_filter(index: int) -> void:
	if turning:
		return
	selected_filter = index
	_update_controls()

func _update_controls() -> void:
	previous_button.disabled = turning or page_index == 0
	next_button.disabled = turning or page_index == PAGE_COUNT - 1
	for i in range(tabs.size()):
		tabs[i].disabled = turning
		tabs[i].set("ink_selected", i == selected_filter)
		tabs[i].add_theme_color_override("font_color", INK if i == selected_filter else Color("8b6a45"))

func turn_page(direction: int) -> void:
	var target := page_index + direction
	if turning or direction not in [-1, 1] or target < 0 or target >= PAGE_COUNT:
		return
	turning = true
	press_active = false
	_update_controls()
	# Next: lift the current leaf. Previous: lay the previous leaf back down.
	var captured := _make_page(page_index if direction > 0 else target)
	snapshot.add_child(captured)
	snapshot.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var start_progress := 0.0 if direction > 0 else 1.0
	var end_progress := 1.0 if direction > 0 else 0.0
	curl.material.set_shader_parameter("progress", start_progress)
	await get_tree().process_frame
	await get_tree().process_frame
	if direction > 0:
		_replace_page(target)
	curl.show()
	turn_tween = create_tween()
	turn_tween.tween_method(_set_curl_progress, start_progress, end_progress, TURN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await turn_tween.finished
	if direction < 0:
		_replace_page(target)
	curl.hide()
	snapshot.remove_child(captured)
	captured.queue_free()
	snapshot.render_target_update_mode = SubViewport.UPDATE_DISABLED
	page_index = target
	turning = false
	_update_controls()
	page_turned.emit(page_index)

func _replace_page(index: int) -> void:
	var child_index := page_content.get_index()
	remove_child(page_content)
	page_content.queue_free()
	page_content = _make_page(index)
	page_content.position = PAGE_ORIGIN
	add_child(page_content)
	move_child(page_content, child_index)

func _set_curl_progress(value: float) -> void:
	curl.material.set_shader_parameter("progress", value)

func _input(event: InputEvent) -> void:
	# Navigation remains usable during a turn; destroying the page cancels its tween.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_LEFT, KEY_RIGHT]:
			turn_page(-1 if event.keycode == KEY_LEFT else 1)
			get_viewport().set_input_as_handled()
	# Touch is also delivered here as an emulated mouse event by project settings.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed:
			press_active = not turning and Rect2(PAGE_ORIGIN + Vector2(100, 138), Vector2(1100, 490)).has_point(local)
			press_position = local
		elif press_active:
			press_active = false
			var delta: Vector2 = local - press_position
			if absf(delta.x) > 90 and absf(delta.x) > absf(delta.y) * 1.4:
				turn_page(1 if delta.x < 0 else -1)
				get_viewport().set_input_as_handled()
