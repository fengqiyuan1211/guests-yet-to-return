@tool
extends Control
## A few drifting dust motes; illustration remains a separate replaceable asset.
var elapsed := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		elapsed += delta
		queue_redraw()

func _draw() -> void:
	for i in range(22):
		var x := 265.0 + fmod(i * 127.3 + elapsed * (2.0 + i % 3), 900.0)
		var y := 230.0 + fmod(i * 71.7 - elapsed * 5.0 + 20000.0, 430.0)
		var alpha := 0.13 + 0.12 * sin(elapsed * 0.7 + i)
		draw_circle(Vector2(x, y), 1.2 + (i % 2) * 0.5, Color(1.0, 0.79, 0.4, alpha))
