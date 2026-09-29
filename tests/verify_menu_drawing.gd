extends Node

const CanvasScript = preload("res://scripts/menu_drawing_canvas.gd")
var canvas: Control
var failures: Array[String] = []
var changed_count := 0


func _ready() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)


func mouse_button(point: Vector2, pressed: bool, emulated := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = canvas.get_global_transform_with_canvas() * point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	if emulated:
		event.device = InputEvent.DEVICE_ID_EMULATION
	get_viewport().push_input(event, true)


func mouse_move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = canvas.get_global_transform_with_canvas() * point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(event, true)


func stroke(from: Vector2, to: Vector2) -> void:
	mouse_button(from, true)
	mouse_move(to)
	mouse_button(to, false)


func touch(point: Vector2, index: int, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = canvas.get_global_transform_with_canvas() * point
	event.index = index
	event.pressed = pressed
	get_viewport().push_input(event, true)


func run() -> void:
	canvas = CanvasScript.new()
	canvas.position = Vector2(30, 30)
	canvas.size = Vector2(540, 720)
	add_child(canvas)
	canvas.strokes_changed.connect(func(): changed_count += 1)
	await get_tree().process_frame
	stroke(Vector2(40, 100), Vector2(460, 100))
	stroke(Vector2(40, 250), Vector2(460, 250))
	var initial: Array = canvas.get_strokes()
	check(initial.size() == 2 and changed_count == 2, "Mouse produces one finished stroke and one signal per gesture")
	check(initial[0].points[0] == [40.0 / 540.0, 100.0 / 720.0], "Stroke positions are normalized")
	canvas.undo()
	check(canvas.get_strokes().size() == 1 and canvas.can_redo(), "Undo removes only the last stroke")
	canvas.redo()
	check(canvas.get_strokes() == initial, "Redo restores the original data")
	canvas.eraser = true
	stroke(Vector2(220, 30), Vector2(220, 310))
	check(canvas.get_strokes().is_empty(), "Fast eraser movement crosses and removes whole strokes")
	canvas.undo()
	check(canvas.get_strokes() == initial, "An eraser gesture restores all crossed strokes in their original order")
	canvas.redo()
	check(canvas.get_strokes().is_empty(), "Erasing can be redone")
	canvas.undo()
	canvas.clear_canvas()
	canvas.undo()
	check(canvas.get_strokes() == initial, "Clearing the page is reversible")
	canvas.eraser = false
	canvas.size = Vector2(270, 360)
	check(canvas.get_strokes() == initial, "Resizing preserves normalized data")
	var serialized: Variant = JSON.parse_string(JSON.stringify(initial))
	canvas.set_strokes(serialized)
	check(JSON.stringify(canvas.get_strokes()) == JSON.stringify(initial) and not canvas.can_undo(), "JSON round trip preserves artwork and resets old history")
	var exported: Array = canvas.get_strokes()
	exported[0].points[0][0] = 0.9
	check(JSON.stringify(canvas.get_strokes()) == JSON.stringify(initial), "Exported data cannot mutate the live drawing")
	canvas.set_strokes([])
	touch(Vector2(50, 50), 0, true)
	mouse_button(Vector2(50, 50), true, true)
	touch(Vector2(150, 150), 1, true)
	touch(Vector2(150, 150), 1, false)
	check(canvas._pointer_kind == 2, "A second finger does not end the active finger")
	touch(Vector2(60, 60), 0, false)
	mouse_button(Vector2(60, 60), false, true)
	check(canvas.get_strokes().size() == 1, "Touch plus emulated mouse records only one stroke")
	stroke(Vector2(100, 100), Vector2(800, 900))
	check(canvas._pointer_kind == 0 and canvas.get_strokes()[-1].points[-1] == [1.0, 1.0], "Outside release is captured and clamped")
	mouse_button(Vector2(70, 70), true)
	var missed_release := InputEventMouseMotion.new()
	missed_release.position = canvas.get_global_transform_with_canvas() * Vector2(75, 75)
	get_viewport().push_input(missed_release, true)
	check(canvas._pointer_kind == 0, "A mouse returning without its button held recovers a missed OS release")
	mouse_button(Vector2(80, 80), true)
	canvas.editable = false
	check(canvas._pointer_kind == 0 and canvas.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Disabling editing commits the current stroke and passes clicks through")
	var count: int = canvas.get_strokes().size()
	stroke(Vector2(90, 90), Vector2(160, 160))
	check(canvas.get_strokes().size() == count, "Read-only paper cannot be drawn on")
	canvas.editable = true
	canvas.set_strokes([{"points": [[NAN, 0.1], ["bad", 0.2], [-0.2, 1.6], [1, 0.8]], "color": "notcolor", "width": 100.0}])
	var clean: Array = canvas.get_strokes()
	check(clean.size() == 1 and clean[0].points.size() == 2 and clean[0].points[0] == [0.0, 1.0], "Malformed and out-of-range stored points are sanitized")
	check(clean[0].width == 64.0 and clean[0].color == "#56361fff", "Invalid color and oversized width are sanitized")
	var many_points: Array = []
	for i in range(21000):
		many_points.append([0.5, 0.5])
	canvas.set_strokes([{"points": many_points}])
	check(canvas.get_strokes()[0].points.size() == 20000, "Point budget caps stored artwork")
	var many_strokes: Array = []
	for i in range(510):
		many_strokes.append({"points": [[0.5, 0.5]]})
	canvas.set_strokes(many_strokes)
	check(canvas.get_strokes().size() == 500, "Stroke budget caps stored artwork")
	print("Menu drawing checks: ", "PASS" if failures.is_empty() else "FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
