extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.47
	var gold := Color("f2cb7e") if TimeManager.fast_forwarding else Color("cba56a")
	draw_arc(center, radius, 0, TAU, 64, gold, 1.1, true)
	for i in range(12):
		var direction := Vector2.from_angle(i * TAU / 12.0 - PI / 2)
		draw_line(center + direction * (radius - 2.7), center + direction * radius, gold, 1.0, true)
	var minutes := TimeManager.visual_minutes()
	var minute_hand := Vector2.from_angle(minutes / 60.0 * TAU - PI / 2)
	var hour_hand := Vector2.from_angle(minutes / 720.0 * TAU - PI / 2)
	draw_line(center, center + hour_hand * radius * 0.51, gold, 2.0, true)
	draw_line(center, center + minute_hand * radius * 0.78, gold, 1.2, true)
	draw_circle(center, 1.8, gold)
