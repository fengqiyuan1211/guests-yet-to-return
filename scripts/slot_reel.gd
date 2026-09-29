extends Control
## A continuous vertical reel strip, with a gradual mechanical stop on its result.
signal stopped
const ICONS := [preload("res://assets/slots/fa-handdrawn.tres"), preload("res://assets/slots/coin-handdrawn.tres"), preload("res://assets/slots/glass-handdrawn.tres"), preload("res://assets/slots/star-handdrawn.tres"), preload("res://assets/slots/lemon-handdrawn.tres"), preload("res://assets/slots/rare-gold.svg")]
var strip: Array[int] = []
var travel := 0.0:
	set(value):
		travel = value
		queue_redraw()
var spinning := false
var result := 0
var motion: Tween

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(64):
		strip.append((i * 3 + 1) % 5)
	strip[0] = result
	queue_redraw()

func spin_to(symbol: int, index: int) -> void:
	spinning = true
	var old_symbol := result
	result = symbol
	travel = 0.0
	# Clear all previous result cells so gold never flashes on a losing spin.
	for i in range(strip.size()):
		strip[i] = (i * 3 + 1) % 5
	strip[0] = old_symbol if old_symbol < 5 else 1
	var final_cell := 24 + index * 7
	strip[final_cell] = symbol
	motion = create_tween()
	motion.tween_property(self, "travel", float(final_cell - 6), 1.3 + index * 0.65).set_trans(Tween.TRANS_LINEAR)
	motion.tween_property(self, "travel", float(final_cell) + 0.035, 1.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	motion.tween_property(self, "travel", float(final_cell), 0.14).set_trans(Tween.TRANS_SINE)
	motion.tween_callback(func():
		spinning = false
		stopped.emit()
	)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("f7e9cb"))
	if strip.is_empty():
		return
	var center := int(floor(travel))
	for cell in range(center - 2, center + 3):
		var symbol := strip[posmod(cell, strip.size())]
		var at := Vector2((size.x - 112) / 2.0, size.y / 2.0 + (cell - travel) * 146 - 56)
		draw_texture_rect(ICONS[symbol], Rect2(at, Vector2(112, 112)), false)
	# Cylindrical shading is strongest near the upper and lower aperture edges.
	for y in range(0, int(size.y), 3):
		var distance := absf((y - size.y / 2.0) / (size.y / 2.0))
		draw_rect(Rect2(0, y, size.x, 3), Color(0.19, 0.12, 0.05, pow(distance, 2.5) * 0.63))
	draw_rect(Rect2(1, 1, size.x - 2, size.y - 2), Color("533a24"), false, 2)
