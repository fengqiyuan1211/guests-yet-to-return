extends Control
## Small ink rules remain separate from the paper texture and data text.
var ink := Color(0.43, 0.29, 0.15, 0.62)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var y := size.y * 0.5
	draw_polyline(PackedVector2Array([Vector2(2, y + 0.2), Vector2(size.x * 0.3, y - 0.3), Vector2(size.x - 2, y + 0.2)]), ink, 1.0, true)
	for x in [4.0, size.x - 4.0]:
		draw_polyline(PackedVector2Array([Vector2(x - 3, y), Vector2(x, y - 3), Vector2(x + 3, y), Vector2(x, y + 3), Vector2(x - 3, y)]), ink, 0.8, true)
