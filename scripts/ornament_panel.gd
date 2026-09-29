@tool
extends Panel
## Draws scalable walnut / parchment detail around native Godot controls.
@export_enum("Walnut", "Parchment") var material_kind: int = 0:
	set(value):
		material_kind = value
		queue_redraw()

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var paper := material_kind == 1
	var ink := Color("865b34") if paper else Color("b6884a")
	ink.a = 0.48
	var inner := Rect2(Vector2(9, 9), size - Vector2(18, 18))
	draw_rect(inner, ink, false, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	for i in range(65 if paper else 30):
		var y := rng.randf_range(14, maxf(15, size.y - 14))
		var x := rng.randf_range(14, maxf(15, size.x - 14))
		var length := rng.randf_range(12, 120)
		var grain := Color(0.27, 0.12, 0.03, 0.025) if paper else Color(0.78, 0.49, 0.22, 0.035)
		draw_line(Vector2(x, y), Vector2(minf(x + length, size.x - 12), y + rng.randf_range(-1, 1)), grain, 1)
	for p in [Vector2(10, 10), Vector2(size.x - 10, 10), Vector2(10, size.y - 10), size - Vector2(10, 10)]:
		draw_circle(p + Vector2(1, 2), 4, Color(0, 0, 0, 0.4))
		draw_circle(p, 3, Color("c49958") if not paper else Color("a47d48"))
		draw_line(p - Vector2(1.5, 0), p + Vector2(1.5, 0), Color("5b381e"), 1)
