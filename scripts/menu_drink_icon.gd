extends Control
## Small ink illustrations; actual recipe thumbnails take precedence in the menu.
var kind := "rocks"
var tint := Color("b67834")

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE

func _draw() -> void:
	var s := minf(size.x, size.y) / 100.0
	draw_set_transform((size - Vector2.ONE * 100.0 * s) * 0.5, 0, Vector2.ONE * s)
	var ink := Color("674321")
	if kind == "highball":
		draw_colored_polygon(PackedVector2Array([Vector2(29, 36), Vector2(70, 36), Vector2(65, 88), Vector2(34, 88)]), tint)
		draw_polyline(PackedVector2Array([Vector2(25, 20), Vector2(32, 90), Vector2(67, 90), Vector2(75, 20), Vector2(25, 20)]), ink, 2.2, true)
		draw_line(Vector2(60, 62), Vector2(73, 7), ink, 2, true)
		for p in [Vector2(44, 41), Vector2(53, 64)]:
			draw_rect(Rect2(p, Vector2(12, 12)), Color(1, 0.96, 0.83, 0.55), false, 1.6)
		draw_circle(Vector2(29, 22), 12, Color("b7ab65"))
		draw_arc(Vector2(29, 22), 12, 0, TAU, 30, ink, 1.4, true)
	elif kind == "coupe":
		draw_colored_polygon(PackedVector2Array([Vector2(20, 32), Vector2(80, 32), Vector2(51, 60)]), tint)
		draw_polyline(PackedVector2Array([Vector2(12, 21), Vector2(50, 62), Vector2(88, 21), Vector2(12, 21)]), ink, 2.2, true)
		draw_line(Vector2(50, 63), Vector2(50, 90), ink, 2.2, true)
		draw_line(Vector2(33, 91), Vector2(68, 91), ink, 2.2, true)
		draw_arc(Vector2(78, 24), 13, -PI, 0, 20, Color("c9913d"), 5, true)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(24, 50), Vector2(78, 50), Vector2(72, 88), Vector2(29, 88)]), tint)
		draw_polyline(PackedVector2Array([Vector2(19, 31), Vector2(27, 91), Vector2(75, 91), Vector2(83, 31), Vector2(19, 31)]), ink, 2.2, true)
		draw_rect(Rect2(36, 45, 23, 26), Color(1, 0.95, 0.80, 0.45), false, 1.8)
		draw_arc(Vector2(72, 33), 17, -PI, 0, 24, Color("bd722a"), 5.0, true)
	draw_line(Vector2(23, 96), Vector2(80, 96), Color(0.4, 0.25, 0.13, 0.25), 1.2, true)
