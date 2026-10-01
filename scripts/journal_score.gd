extends Control
## Ink gauges have no text-driven minimum size, so their stroke stays slim.
var value := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.50, 0.34, 0.16, 0.035)
	background.border_color = Color(0.35, 0.24, 0.12, 0.68)
	background.set_border_width_all(1)
	background.set_corner_radius_all(3)
	draw_style_box(background, Rect2(Vector2.ZERO, size))
	var width := (size.x - 2) * clampf(value, 0, 100) / 100.0
	if width > 0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.35, 0.23, 0.12, 0.78)
		fill.set_corner_radius_all(2)
		draw_style_box(fill, Rect2(1, 1, width, size.y - 2))
