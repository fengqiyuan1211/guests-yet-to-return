extends Button
## One physical object, one hit polygon; keyboard focus gets the same highlight.
var outline:=PackedVector2Array()

func _ready() -> void:
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","focus"]: add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _has_point(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point,outline)

func _draw() -> void:
	if outline.size()<3 or not (is_hovered() or has_focus()): return
	draw_colored_polygon(outline,Color(1,.79,.38,.075))
	var border:=outline.duplicate()
	border.append(outline[0])
	draw_polyline(border,Color(1,.8,.44,.9),2.5,true)
