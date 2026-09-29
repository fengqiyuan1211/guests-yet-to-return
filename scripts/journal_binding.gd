extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	for y in [106.0, 354.0, 601.0]:
		draw_circle(Vector2(12, y + 3), 13, Color("21170e"))
		draw_circle(Vector2(57, y + 3), 13, Color("55321c"))
		draw_circle(Vector2(57, y + 3), 8, Color("281c12"))
		var ring := PackedVector2Array()
		for i in range(49):
			var angle := TAU * i / 48.0
			ring.append(Vector2(34 + cos(angle) * 27, y + sin(angle) * 9))
		draw_polyline(ring, Color(0.12, 0.06, 0.03, 0.75), 11.0, true)
		draw_polyline(ring, Color("9c672d"), 7.0, true)
		for i in range(ring.size()):
			ring[i] += Vector2(0, -1.5)
		draw_polyline(ring, Color("dbb66c"), 2.5, true)
