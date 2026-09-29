extends Control
var active := false
var jackpot := false
var elapsed := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	# Marquee bulbs; brass fittings keep their shape even when unlit.
	for i in range(19):
		var x := 558.0 + i * 30.0
		var p := Vector2(x, 257 - sin(i / 18.0 * PI) * 8)
		var on := jackpot or (active and posmod(i + int(elapsed * 9), 4) == 0)
		draw_circle(p, 5.5, Color("5b4024"))
		if on:
			draw_circle(p, 11, Color(1, 0.65, 0.2, 0.13))
		draw_circle(p, 3.8, Color("ffe7aa") if on else Color("bf9451"))
	# Steam dissipates above the copper exhaust during operation.
	if active:
		for i in range(10):
			var age := fmod(elapsed * 0.55 + i / 10.0, 1.0)
			var p := Vector2(1131 + sin(age * 5 + i) * 10, 158 - age * 95)
			draw_circle(p, 3 + age * 16, Color(0.94, 0.85, 0.66, (1 - age) * 0.1))
	# Pressure gauge, animated while the reels spin.
	var center := Vector2(1321, 400)
	draw_circle(center + Vector2(2, 5), 74, Color("080b0a"))
	draw_circle(center, 72, Color("856131"))
	draw_circle(center, 65, Color("dfc28a"))
	draw_circle(center, 57, Color("e9ddba"))
	for i in range(21):
		var angle := deg_to_rad(140 + i * 13)
		var axis := Vector2.from_angle(angle)
		draw_line(center + axis * 46, center + axis * (38 if i % 5 == 0 else 42), Color("5b4b34"), 2, true)
	var needle := deg_to_rad(220 + (sin(elapsed * 7) * 7 + 95 if active else 0))
	draw_line(center, center + Vector2.from_angle(needle) * 36, Color("a63e27"), 3, true)
	draw_circle(center, 5, Color("665135"))
	# Exposed pair of cogwheels below the gauge.
	for i in range(2):
		var c := Vector2(1294 + i * 67, 550 + i * 25)
		var rotation := elapsed * (1.2 if i == 0 else -1.2) if active else float(i)
		for tooth in range(12):
			var a := rotation + tooth * TAU / 12.0
			draw_line(c + Vector2.from_angle(a) * 22, c + Vector2.from_angle(a) * 34, Color("b68b49"), 9, true)
		draw_circle(c, 27, Color("8b673a"))
		draw_circle(c, 20, Color("2e281e"))
		for spoke in range(5):
			var a := rotation + spoke * TAU / 5.0
			draw_line(c, c + Vector2.from_angle(a) * 21, Color("b18d51"), 5, true)
		draw_circle(c, 7, Color("d7b97e"))
