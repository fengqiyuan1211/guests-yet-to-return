extends Button
## Typography on parchment; the control keeps native keyboard/touch semantics.
var ink_selected := false:
	set(value):
		ink_selected = value
		queue_redraw()
var is_margin := false

func _ready() -> void:
	for event in [mouse_entered, mouse_exited, focus_entered, focus_exited, button_down, button_up]:
		event.connect(queue_redraw)

func _draw() -> void:
	if disabled or not (ink_selected or has_focus() or is_hovered()):
		return
	var width := get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size")).x
	width = minf(width + 12.0, size.x - 20.0)
	var start := (size.x - width) * 0.5
	var baseline := size.y * 0.5 + 25.0 if is_margin else size.y - 4.0
	var ink := Color("714422")
	ink.a = 0.72 if ink_selected else 0.38
	var stroke := PackedVector2Array([
		Vector2(start, baseline + 0.8),
		Vector2(start + width * 0.23, baseline - 0.3),
		Vector2(start + width * 0.63, baseline + 0.4),
		Vector2(start + width, baseline - 0.7)
	])
	draw_polyline(stroke, ink, 1.7 if ink_selected else 1.0, true)
	if ink_selected:
		draw_line(Vector2(start + 4, baseline + 3.0), Vector2(start + width - 9, baseline + 2.2), Color(0.44, 0.27, 0.13, 0.24), 0.8, true)
