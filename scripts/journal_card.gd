extends Control
## Faint pen registration marks on the same paper, without a separate card surface.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var ink := Color(0.37, 0.25, 0.14, 0.23)
	# Small irregular open corners suggest six future illustrations without framing them as buttons.
	for corner in [Vector2(10, 12), Vector2(size.x - 10, 12), Vector2(size.x - 10, size.y - 18), Vector2(10, size.y - 18)]:
		var inward := Vector2(1 if corner.x < size.x * 0.5 else -1, 1 if corner.y < size.y * 0.5 else -1)
		var stroke := PackedVector2Array([
			corner + Vector2(0.7, 15 * inward.y),
			corner + Vector2.ZERO,
			corner + Vector2(16 * inward.x, 0.5)
		])
		draw_polyline(stroke, ink, 0.9, true)
	var y := size.y - 37
	draw_polyline(PackedVector2Array([
		Vector2(42, y + 0.3), Vector2(106, y - 0.3),
		Vector2(194, y + 0.5), Vector2(size.x - 42, y - 0.4)
	]), Color(0.37, 0.25, 0.14, 0.27), 1.0, true)
