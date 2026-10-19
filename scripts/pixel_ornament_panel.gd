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
	for p in [Vector2(12,12),Vector2(size.x-16,12),Vector2(12,size.y-16),size-Vector2(16,16)]:
		draw_rect(Rect2(p,Vector2(4,4)),Color("c49958"))
