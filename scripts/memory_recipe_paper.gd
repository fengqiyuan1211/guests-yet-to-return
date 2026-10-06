extends Control
signal close_requested
const FONT := preload("res://assets/fonts/NotoSerifSC.ttf")
var sheet: Control
var allow_research_link := true

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var veil := ColorRect.new()
	veil.color = Color(0.1, 0.07, 0.04, 0.8)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	sheet = Control.new()
	add_child(sheet)
	var paper := Paper.new()
	paper.size = Vector2(1600, 900)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(paper)
	var close := Button.new()
	close.position = Vector2(955, 121)
	close.size = Vector2(54, 46)
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "pressed", "focus"]: close.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["hover", "hover_pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("dec598")
		style.set_corner_radius_all(4)
		close.add_theme_stylebox_override(state, style)
	close.add_theme_font_override("font", FONT)
	close.add_theme_font_size_override("font_size", 34)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]: close.add_theme_color_override(state, Color("654c32"))
	close.pressed.connect(_close)
	sheet.add_child(close)
	_populate_recipe()
	resized.connect(_fit)
	_fit()

func _text(rect: Rect2, value: String, px: int, color := Color("654c32")) -> Label:
	var label := Label.new()
	label.position=rect.position
	label.size=rect.size
	label.text=value
	label.add_theme_font_override("font",FONT)
	label.add_theme_font_size_override("font_size",px)
	label.add_theme_color_override("font_color",color)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	sheet.add_child(label)
	return label

func _populate_recipe() -> void:
	var ref := preload("res://scripts/research_data.gd").legendary("childhood_keepsake")
	if ref.is_empty(): return
	_text(Rect2(554,277,475,28),"高球杯  /  方冰 100 g",18,Color("99784a"))
	var y:=315.0
	for row: Dictionary in ref.ingredients:
		_text(Rect2(555,y,355,29),str(row.name),21)
		var amount:=_text(Rect2(909,y,118,29),"%s %s" % [WorkbenchSession.format_amount(float(row.amount)),"颗" if row.unit=="piece" else row.unit],21)
		amount.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		y+=34
	_text(Rect2(555,502,470,95),"杯中加冰，量取酒与青柠汁。\n加入可乐后轻搅 3—6 秒，放上樱桃。\n留住气泡，不用摇和。",20)
	var badge:=Panel.new()
	badge.position=Vector2(555,607)
	badge.size=Vector2(475,66)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("59402a")
	style.border_color=Color("cba454")
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	badge.add_theme_stylebox_override("panel",style)
	sheet.add_child(badge)
	_text(Rect2(576,611,438,31),"传说 · 未完待续",23,Color("f4d98c"))
	_text(Rect2(576,644,438,24),"有些故事只是暂时停在这里。",16,Color("e0c798"))
	if allow_research_link and WorkbenchSession.research_state().acquired.has(ref.id):
		var button:=Button.new()
		button.position=Vector2(634,741)
		button.size=Vector2(320,42)
		button.text="带着酒单去研习  →"
		button.focus_mode=Control.FOCUS_NONE
		button.add_theme_font_override("font",FONT)
		button.add_theme_font_size_override("font_size",21)
		for state in ["normal","hover","pressed","focus"]: button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		button.add_theme_color_override("font_color",Color("654c32"))
		button.add_theme_color_override("font_hover_color",Color("a8732a"))
		button.pressed.connect(func():
			Navigation.research_view="legendary"
			Navigation.go_to(&"research"))
		sheet.add_child(button)

func _fit() -> void:
	var factor := minf(size.x / 1600, size.y / 900)
	sheet.scale = Vector2.ONE * factor
	sheet.position = (size - Vector2(1600, 900) * factor) * 0.5

func _close() -> void:
	close_requested.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()

class Paper extends Control:
	func _draw() -> void:
		var ink := Color("654c32")
		draw_rect(Rect2(501, 117, 618, 691), Color(0.08, 0.04, 0.01, 0.25))
		var edge := PackedVector2Array([Vector2(495,105),Vector2(1105,112),Vector2(1094,221),Vector2(1102,341),Vector2(1098,690),Vector2(1103,793),Vector2(497,801),Vector2(488,674),Vector2(493,353),Vector2(487,196)])
		draw_colored_polygon(edge, Color("ead3a6"))
		draw_polyline(edge, Color("b99b6d"), 2, true)
		draw_rect(Rect2(518, 131, 559, 637), Color("f1dfbd"))
		for i in range(45):
			var p := Vector2(535 + fmod(i * 79, 519), 148 + fmod(i * 103, 605))
			draw_circle(p, 0.8, Color(0.4, 0.25, 0.08, 0.15))
		var title := "童年拾忆"
		var width := FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 45).x
		draw_string(FONT, Vector2(800 - width / 2, 234), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 45, ink)
		draw_line(Vector2(587, 261), Vector2(1013, 261), Color("bda579"), 1, true)
		for y in [344, 378, 412, 446, 480]:
			draw_line(Vector2(571, y), Vector2(1026, y + 1), Color(0.5, 0.37, 0.2, 0.21), 1, true)
		# A faint crease, worn corners and a small original shuttlecock sketch.
		draw_line(Vector2(520, 461), Vector2(1075, 455), Color(0.6, 0.47, 0.28, 0.12), 2, true)
		draw_line(Vector2(800, 140), Vector2(798, 752), Color(0.6, 0.47, 0.28, 0.08), 1, true)
		draw_arc(Vector2(995, 699), 39, 0, TAU, 32, Color(0.45, 0.28, 0.12, 0.3), 1, true)
		var feathers := PackedVector2Array([Vector2(975,680),Vector2(1016,684),Vector2(1000,713),Vector2(990,713)])
		draw_polyline(feathers, Color("a58960"), 1.5, true)
		for x in [984,994,1005]: draw_line(Vector2(x,683),Vector2(995,712),Color("a58960"),1,true)
		draw_circle(Vector2(995,715),5,Color("a58960"))
		draw_string(FONT, Vector2(555, 721), "小线赠予", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("a58960"))
