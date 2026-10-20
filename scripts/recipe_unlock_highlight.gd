extends Control
## A quiet pixel border, shared by the catalogue entry and newly learned recipes.
var clock := 0.0
var active := false:
	set(value):
		active = value
		visible = value
		set_process(value)
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	active = active

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	clock = fmod(clock + delta,3.2)
	queue_redraw()

func _draw() -> void:
	if not active: return
	var pulse := 0.5 if OpeningFlow.reduced_motion else (sin(clock / 3.2 * TAU) + 1.0) * 0.5
	var color := Color("d7ae69")
	color.a = 0.40 + pulse * 0.27
	var rect := Rect2(Vector2(6,6),size-Vector2(12,12))
	draw_rect(rect,color,false,2)
	for corner in [rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]:
		var inward := Vector2(1 if corner.x < size.x/2 else -1,1 if corner.y < size.y/2 else -1)
		draw_line(corner,corner+Vector2(12*inward.x,0),color,3)
		draw_line(corner,corner+Vector2(0,12*inward.y),color,3)
