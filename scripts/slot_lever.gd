extends Button
## Click/tap the red handle. The visible rod pivots and compresses downwards.
var pull := 0.0:
	set(value):
		pull = value
		queue_redraw()

func _ready() -> void:
	text = ""
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "拉动拉杆 · 20 金币一次"

func animate_pull() -> Tween:
	var tween := create_tween()
	tween.tween_property(self, "pull", 1.0, 0.27).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_interval(0.09)
	tween.tween_property(self, "pull", 0.0, 0.48).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween

func _draw() -> void:
	var pivot := Vector2(47, 227)
	var knob := Vector2(59 + sin(pull * PI) * 22, 47 + pull * 227)
	draw_circle(pivot + Vector2(3, 4), 35, Color("110e0a"))
	draw_circle(pivot, 31, Color("8e622e"))
	draw_circle(pivot, 25, Color("e2bf73"))
	draw_circle(pivot, 17, Color("342b22"))
	draw_line(pivot + Vector2(5, 4), knob + Vector2(5, 4), Color(0, 0, 0, 0.6), 20, true)
	draw_line(pivot, knob, Color("554d3f"), 19, true)
	draw_line(pivot - Vector2(2, 0), knob - Vector2(2, 0), Color("b6b4a4"), 12, true)
	draw_line(pivot - Vector2(5, 0), knob - Vector2(5, 0), Color("f0e9d0"), 3, true)
	draw_circle(knob + Vector2(3, 5), 31, Color("230e0a"))
	draw_circle(knob, 29, Color("6e211b"))
	draw_circle(knob - Vector2(3, 4), 25, Color("b83b28"))
	draw_circle(knob - Vector2(8, 11), 14, Color("e66c40"))
	draw_circle(knob - Vector2(12, 16), 6, Color("ffbe83"))
	if has_focus() and not disabled:
		draw_arc(knob, 35, 0, TAU, 48, Color("e9c87e"), 2, true)
