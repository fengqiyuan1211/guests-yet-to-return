extends Button
## Every card is a native input control; pictures and labels are separate children.
var has_recipe := false
var is_locked := true

func _ready() -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for event in [mouse_entered, mouse_exited, focus_entered, focus_exited, button_down, button_up]:
		event.connect(queue_redraw)

func _draw() -> void:
	var ink := Color(0.37, 0.25, 0.14, 0.60 if has_recipe else 0.22)
	if has_recipe and not disabled and (is_hovered() or has_focus()):
		ink = Color(0.34, 0.19, 0.07, 0.92)
	var rect := Rect2(9, 9, size.x - 18, size.y - 20)
	if has_recipe:
		draw_style_box(_frame(ink), rect)
		draw_style_box(_frame(Color(ink, ink.a * 0.48)), rect.grow(-4))
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var inward := Vector2(1 if corner.x < size.x * 0.5 else -1, 1 if corner.y < size.y * 0.5 else -1)
		draw_polyline(PackedVector2Array([corner + Vector2(0, 17 * inward.y), corner, corner + Vector2(17 * inward.x, 0)]), ink, 1.0, true)
		if has_recipe:
			draw_arc(corner + inward * 10, 4, 0, TAU, 16, ink, 0.8, true)
	var y := size.y - 45
	draw_polyline(PackedVector2Array([Vector2(30, y + 0.3), Vector2(size.x * 0.5, y - 0.3), Vector2(size.x - 30, y + 0.2)]), Color(ink, ink.a * 0.6), 0.8, true)
	if has_recipe and is_locked:
		var center := Vector2(29, size.y - 28)
		draw_arc(center + Vector2(0, -4), 4.2, PI, TAU, 12, ink, 1.8, true)
		draw_rect(Rect2(center + Vector2(-5.8, -4), Vector2(11.6, 10)), ink, true)
		draw_circle(center + Vector2(0, 0.2), 1.1, Color("e0bf88"))
		draw_line(center + Vector2(0, 0.5), center + Vector2(0, 3), Color("e0bf88"), 0.9, true)

func _frame(ink: Color) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = Color.TRANSPARENT
	result.border_color = ink
	result.set_border_width_all(1)
	result.set_corner_radius_all(8)
	return result
