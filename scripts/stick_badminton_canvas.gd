extends Control
const FONT := preload("res://assets/fonts/NotoSerifSC.ttf")
const INK := Color("453529")
var model: RefCounted
var elapsed := 0.0
var trail: Array[Vector2] = []
var paused := false
var practice_mode := true

func _draw() -> void:
	_frame()
	_scoreboard()
	_yard()
	if model == null: return
	if model.phase == "rally" and model.last_hitter == 1:
		_landing_marker()
	if model.player_can_return():
		# Readiness follows the model's actual racket sweep, rather than a second reach arc.
		draw_circle(model.shuttle, 17, Color(0.48, 0.62, 0.31, 0.14))
		draw_arc(model.shuttle, 18, -0.6, 0.6, 12, Color(0.42, 0.53, 0.31, 0.55), 2, true)
		draw_arc(model.shuttle, 18, PI - 0.6, PI + 0.6, 12, Color(0.42, 0.53, 0.31, 0.55), 2, true)
	_figure(Vector2(model.player_x, 650 + model.player_jump), false, 0, float(model.player_move))
	_figure(Vector2(model.ai_x, 650 + model.ai_jump), true, 1, float(model.ai_move))
	for i in range(trail.size()):
		draw_circle(trail[i], 1.5 + i * 0.35, Color(0.5, 0.38, 0.24, (i + 1) * 0.025))
	if model.hit_flash > 0: _hit_feedback()
	var ball_angle: float = model.velocity.angle() if model.phase == "rally" else -PI / 2
	_shuttle(model.shuttle, ball_angle)
	var toast: String = model.toast
	if model.practice_left > 0: toast = "热身 · 还剩 %d 球    " % model.practice_left + toast
	draw_string(FONT, Vector2(118, 222), toast, HORIZONTAL_ALIGNMENT_LEFT, -1, 23, INK)
	_center("你", Vector2(model.player_x, 681), 19, Color("57745b"))
	_center("小线", Vector2(model.ai_x, 681), 19, Color("8b5236"))
	var hint: String = "比赛已暂停" if paused else model.action_hint()
	var hint_color := Color("48653c") if model.player_can_return() else Color("785738")
	var hint_width := FONT.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	draw_style_box(_paper_box(Color("f6e7c7"), Color("c5aa7b"), 6), Rect2(800 - (hint_width + 52) / 2, 705, hint_width + 52, 34))
	_center(hint, Vector2(800, 729), 21, hint_color)

func _frame() -> void:
	draw_rect(Rect2(0, 0, 1600, 900), Color("261c16"))
	draw_rect(Rect2(20, 18, 1560, 864), Color("775434"))
	for i in range(14):
		var y := 22 + i * 62
		draw_line(Vector2(22, y), Vector2(1578, y + 2), Color("63472f"), 1, true)
	draw_rect(Rect2(31, 29, 1538, 842), Color("eddcba"))
	draw_rect(Rect2(44, 42, 1512, 816), Color("fbefd1"), false, 2)
	for i in range(70):
		var p := Vector2(58 + fmod(i * 137.0, 1479), 54 + fmod(i * 73.0, 789))
		draw_circle(p, 0.7, Color(0.44, 0.30, 0.14, 0.12))
	for x in [45, 1555]:
		for y in [43, 858]:
			draw_circle(Vector2(x, y), 4, Color("ae8149"))
			draw_line(Vector2(x - 15, y), Vector2(x + 15, y), Color("b89159"), 1, true)
	draw_string(FONT, Vector2(90, 98), "童年拾忆", HORIZONTAL_ALIGNMENT_LEFT, -1, 42, INK)
	draw_string(FONT, Vector2(93, 134), "酒馆后院  /  练习赛" if practice_mode else "酒馆后院  /  老朋友的球局", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("8a6e51"))
	draw_line(Vector2(93, 149), Vector2(315, 149), Color("b59870"), 1, true)

func _scoreboard() -> void:
	draw_style_box(_paper_box(Color("563e29"), Color("a77b42"), 5), Rect2(580, 48, 440, 115))
	draw_rect(Rect2(588, 56, 424, 99), Color("c2a376"), false, 1)
	var scores := [0, 0]
	if model != null:
		scores = [model.player_score, model.ai_score]
		if model.phase == "point":
			var pulse := clampf(model.point_delay / 1.35, 0, 1)
			var pulse_color := Color("72875a") if model.point_winner == 0 else Color("ad7047")
			pulse_color.a = pulse
			draw_rect(Rect2(578, 46, 444, 119), pulse_color, false, 3)
	for side in range(2):
		var x := 690.0 + side * 220
		_center("你" if side == 0 else "小线", Vector2(x, 79), 20, Color("d7bf94"))
		_center(str(scores[side]), Vector2(x, 127), 43, Color("fff1d6"))
		for i in range(5):
			var p := Vector2(x - 38 + i * 19, 143)
			draw_circle(p, 4.5, Color("d8bd8b") if i < scores[side] else Color("795b3c"))
	_center(":", Vector2(800, 119), 34, Color("bfa175"))

func _yard() -> void:
	draw_style_box(_paper_box(Color("e1c8a0"), Color("bea077"), 2), Rect2(91, 175, 1418, 522))
	for i in range(13):
		var tone := Color("f0dfb9").lerp(Color("d6b686"), float(i) / 13)
		draw_rect(Rect2(104, 189 + i * 28, 1392, 29), tone)
	# Distant roofs, then a filled timber fence: all scenery is behind the players.
	draw_colored_polygon(PackedVector2Array([Vector2(104, 412), Vector2(104, 328), Vector2(241, 284), Vector2(360, 328), Vector2(470, 303), Vector2(610, 341), Vector2(727, 300), Vector2(840, 335), Vector2(964, 277), Vector2(1106, 321), Vector2(1293, 281), Vector2(1496, 346), Vector2(1496, 553), Vector2(104, 553)]), Color("cfb589"))
	for i in range(17):
		var x := 104.0 + i * 82
		var top := 376 + sin(i * 1.7) * 10
		var color := Color("c9ac80") if i % 2 == 0 else Color("d3b98e")
		draw_rect(Rect2(x, top, 80, 181), color)
		draw_rect(Rect2(x, top, 80, 181), Color("b89c73"), false, 1)
		for offset in [18, 55]:
			draw_line(Vector2(x + offset, top + 13), Vector2(x + offset - 2, 548), Color("bfa277"), 1, true)
		for y in [419, 510]: draw_circle(Vector2(x + 40, y), 1.9, Color("a1845f"))
	for y in [426, 508]:
		draw_rect(Rect2(104, y, 1392, 11), Color("b89b70"))
		draw_line(Vector2(104, y), Vector2(1496, y), Color("e4c999"), 1, true)
	draw_polyline(PackedVector2Array([Vector2(110, 279), Vector2(450, 310), Vector2(805, 322), Vector2(1160, 310), Vector2(1490, 279)]), Color("8f7858"), 2, true)
	for i in range(9):
		var p := Vector2(150 + i * 160, 281 + sin(i * PI / 8) * 42)
		draw_circle(p + Vector2(0, 10), 16, Color(0.9, 0.7, 0.3, 0.14))
		draw_line(p, p + Vector2(0, 8), Color("8f7858"), 2, true)
		draw_rect(Rect2(p + Vector2(-6, 5), Vector2(12, 16)), Color("f2d195"))
		draw_rect(Rect2(p + Vector2(-6, 5), Vector2(12, 16)), Color("b28a50"), false, 1)
		draw_line(p + Vector2(-8, 5), p + Vector2(8, 5), Color("8d6b43"), 2, true)
	for i in range(5):
		draw_rect(Rect2(104, 552 + i * 26, 1392, 27), Color("ad936c").lerp(Color("967c59"), float(i) / 5))
	for x in range(160, 1450, 78): draw_line(Vector2(x, 560), Vector2(x - 76, 682), Color("c6b08b"), 1, true)
	draw_rect(Rect2(158, 568, 1284, 85), Color("ead6ac"), false, 2)
	for x in [453, 1147]: draw_line(Vector2(x, 569), Vector2(x - 26, 650), Color("e0cba3"), 1, true)
	draw_line(Vector2(155, 650), Vector2(1445, 650), Color("f9edc8"), 4, true)
	draw_line(Vector2(800, 434), Vector2(800, 651), Color("6c543d"), 5, true)
	draw_line(Vector2(776, 434), Vector2(824, 434), Color("fbf1dc"), 4, true)
	for y in range(446, 650, 15): draw_line(Vector2(779, y), Vector2(821, y + 1), Color("786d57"), 1, true)
	for x in [780, 790, 810, 820]: draw_line(Vector2(x, 435), Vector2(x, 650), Color("786d57"), 1, true)

func _center(text: String, point: Vector2, px: int, color: Color) -> void:
	var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	draw_string(FONT, point - Vector2(width / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)

func _paper_box(fill: Color, edge: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(2)
	box.set_corner_radius_all(radius)
	return box

func _landing_marker() -> void:
	var x := clampf(model.predicted_landing(), 157, 775)
	var color := Color("6d7b54")
	color.a = 0.65
	draw_line(Vector2(x - 25, 645), Vector2(x + 25, 645), color, 3, true)
	draw_arc(Vector2(x, 645), 17, PI, TAU, 20, color, 2, true)
	draw_line(Vector2(x, 638), Vector2(x, 624), color, 2, true)
	draw_string(FONT, Vector2(x - 21, 615), "落点", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, color)

func _hit_feedback() -> void:
	var progress: float = 1 - model.hit_flash / 0.23
	var color := Color("f8ecad")
	color.a = 1 - progress
	var p: Vector2 = model.hit_position
	draw_circle(p, 10 + progress * 14, Color(0.94, 0.73, 0.29, (1 - progress) * 0.24))
	draw_arc(p, 12 + progress * 22, 0, TAU, 24, color, 2, true)
	for i in range(6):
		var direction := Vector2.from_angle(i * TAU / 6)
		draw_line(p + direction * (19 + progress * 12), p + direction * (29 + progress * 18), color, 2, true)
	if model.last_hitter == 0:
		var ink := Color("6a7d45")
		ink.a = 1 - progress
		draw_string(FONT, p + Vector2(-20, -33 - progress * 12), model.hit_quality, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, ink)

func _figure(base: Vector2, cowboy: bool, who: int, movement: float) -> void:
	var direction := -1.0 if cowboy else 1.0
	var pose: Dictionary = model.racket_pose(who)
	var swing_left: float = float(model.player_swing) if who == 0 else float(model.ai_swing)
	var progress := clampf(1.0 - swing_left / float(model.SWING_DURATION), 0.0, 1.0)
	var shadow := Vector2(base.x, 654)
	draw_set_transform(shadow, 0, Vector2(1, 0.2))
	draw_circle(Vector2.ZERO, 26, Color(0.4, 0.32, 0.24, 0.25))
	draw_set_transform(Vector2.ZERO)
	var head_lean := sin(progress * PI) * 14.0 if swing_left > 0 and pose.type == "overhand" else 0.0
	var head := base + Vector2(-direction * head_lean, -150)
	var stride := sin(elapsed * 12) * 8 * absf(movement)
	if base.y < 644: stride = 10
	draw_polyline(PackedVector2Array([base + Vector2(0, -122), base + Vector2(1, -62), base + Vector2(-23 + stride, -2)]), INK, 4, true)
	draw_line(base + Vector2(0, -122), head + Vector2(0, 24), INK, 4, true)
	draw_line(base + Vector2(1, -62), base + Vector2(25 - stride, -2), INK, 4, true)
	var shoulder: Vector2 = pose.shoulder
	var hand: Vector2 = pose.hand
	var counter_lift := sin(progress * PI) * 13.0 if swing_left > 0 else 0.0
	draw_polyline(PackedVector2Array([base + Vector2(0, -109), base + Vector2(-direction * 19, -94 - counter_lift), base + Vector2(-direction * 32, -81 - counter_lift)]), INK, 3, true)
	if swing_left > 0:
		_stroke_trail(who, progress, str(pose.type))
	# Keep the holding arm simple; the extra folded segment looked like a bent shaft.
	draw_line(shoulder, hand, INK, 3.5, true)
	draw_circle(hand, 2.8, INK)
	_racket(pose)
	# The backswing passes behind the head instead of drawing an arm across the face.
	draw_circle(head, 27, Color("f9f0d9"))
	draw_arc(head, 27, 0, TAU, 32, INK, 3, true)
	for dx in [-8, 8]: draw_circle(head + Vector2(dx, -1), 2.1, INK)
	draw_line(head + Vector2(-6, 11), head + Vector2(6, 10), INK, 2, true)
	if not cowboy:
		draw_line(base + Vector2(-11, -115), base + Vector2(12, -115), Color("68816d"), 8, true)
	if cowboy:
		draw_colored_polygon(PackedVector2Array([head + Vector2(-26, -21), head + Vector2(-18, -48), head + Vector2(12, -49), head + Vector2(22, -20)]), Color("86613e"))
		draw_line(head + Vector2(-39, -22), head + Vector2(38, -18), INK, 5, true)
		draw_line(head + Vector2(-16, -28), head + Vector2(18, -27), Color("c7a064"), 5, true)
		draw_colored_polygon(PackedVector2Array([base + Vector2(-12, -117), base + Vector2(13, -116), base + Vector2(0, -95), base + Vector2(-12, -69)]), Color("b56442"))

func _stroke_trail(who: int, progress: float, stroke_type: String) -> void:
	if progress < 0.12 or progress > 0.94: return
	var points := PackedVector2Array()
	var start := maxf(0.12, progress - 0.19)
	for i in range(7):
		var sampled: Dictionary = model.racket_pose(who, lerpf(start, progress, float(i) / 6.0))
		points.append(sampled.center)
	var stroke_color := Color("ac8751") if stroke_type == "overhand" else Color("81905b")
	for i in range(points.size() - 1):
		var color := stroke_color
		color.a = 0.08 + float(i + 1) * 0.037
		draw_line(points[i], points[i + 1], color, 2.4, true)
	if points.size() > 3:
		var tangent := (points[-1] - points[-3]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var motion_color := stroke_color
		motion_color.a = 0.28
		for side in [-1.0, 1.0]:
			var p: Vector2 = points[-3] + normal * side * 12.0
			draw_line(p - tangent * 9.0, p + tangent * 6.0, motion_color, 1.5, true)

func _racket(pose: Dictionary) -> void:
	var hand: Vector2 = pose.hand
	var center: Vector2 = pose.center
	var angle: float = pose.angle
	var radii: Vector2 = pose.racket_radii
	var grip := (center - hand).normalized()
	var neck := center - grip * radii.y
	# Shaft and head stay on one straight axis; only the player's elbow bends.
	draw_line(hand, neck, Color("4b4941"), 2.7, true)
	draw_line(hand + grip * 2.0, hand + grip * 17.0, Color("9b6c43"), 5.5, true)
	var outline := PackedVector2Array()
	for i in range(33): outline.append(center + Vector2(cos(i * TAU / 32) * radii.x, sin(i * TAU / 32) * radii.y).rotated(angle))
	draw_colored_polygon(outline, Color("f2e6ce"))
	draw_polyline(outline, INK, 3, true)
	for ratio in [-0.5, 0.0, 0.5]:
		var edge_y := radii.y * sqrt(1.0 - ratio * ratio) * 0.86
		draw_line(center + Vector2(radii.x * ratio, -edge_y).rotated(angle), center + Vector2(radii.x * ratio, edge_y).rotated(angle), Color("af9270"), 1, true)
	for ratio in [-0.6, -0.3, 0.0, 0.3, 0.6]:
		var edge_x := radii.x * sqrt(1.0 - ratio * ratio) * 0.86
		draw_line(center + Vector2(-edge_x, radii.y * ratio).rotated(angle), center + Vector2(edge_x, radii.y * ratio).rotated(angle), Color("af9270"), 1, true)

func _shuttle(p: Vector2, angle: float) -> void:
	var fan := PackedVector2Array([p + Vector2(-19, -11).rotated(angle), p + Vector2(-19, 11).rotated(angle), p + Vector2(5, 4).rotated(angle), p + Vector2(5, -4).rotated(angle)])
	draw_colored_polygon(fan, Color("fff9e9"))
	draw_polyline(fan, INK, 2.1, true)
	for offset in [-6, 0, 6]: draw_line(p + Vector2(-18, offset).rotated(angle), p + Vector2(4, 0).rotated(angle), Color("a18b70"), 1, true)
	draw_circle(p + Vector2(5, 0).rotated(angle), 5, Color("f6e9cc"))
