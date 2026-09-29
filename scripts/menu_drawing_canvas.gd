extends Control
## Transparent ink overlay. Points are normalized; widths use a 540 px paper.
## The eraser removes whole strokes and leaves paper and printed text intact.

signal strokes_changed

const MAX_POINTS := 20000
const MAX_STROKES := 500
const REFERENCE_WIDTH := 540.0
const MAX_HISTORY_ACTIONS := 64
const MAX_HISTORY_POINTS := 80000

var ink_color: Color = Color("56361f")
var brush_width: float = 4.0
var eraser: bool = false:
	set(value):
		if eraser != value:
			_finish_gesture()
		eraser = value
var editable: bool = true:
	set(value):
		if not value:
			_finish_gesture()
		editable = value
		mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE

var _strokes: Array[Dictionary] = []
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _point_count := 0
var _pointer_kind := 0 # 0: none, 1: mouse, 2: touch
var _touch_index := -1
var _last_position := Vector2.ZERO
var _active_stroke: Dictionary = {}
var _erased: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	resized.connect(queue_redraw)


func set_strokes(value: Array) -> void:
	_reset_gesture()
	_strokes.clear()
	_undo_stack.clear()
	_redo_stack.clear()
	_point_count = 0
	for raw in value:
		if _strokes.size() >= MAX_STROKES or _point_count >= MAX_POINTS:
			break
		if not raw is Dictionary or not raw.get("points") is Array:
			continue
		var points: Array = []
		for point in raw.points:
			if _point_count + points.size() >= MAX_POINTS:
				break
			if not point is Array or point.size() != 2:
				continue
			if not _finite_number(point[0]) or not _finite_number(point[1]):
				continue
			points.append([clampf(float(point[0]), 0.0, 1.0), clampf(float(point[1]), 0.0, 1.0)])
		if points.is_empty():
			continue
		var color := str(raw.get("color", "#56361fff"))
		if not Color.html_is_valid(color):
			color = "#56361fff"
		var width: Variant = raw.get("width", 4.0)
		if not _finite_number(width):
			width = 4.0
		_strokes.append({"points": points, "color": "#" + Color.html(color).to_html(true), "width": clampf(float(width), 1.0, 64.0)})
		_point_count += points.size()
	queue_redraw()
	strokes_changed.emit()


func get_strokes() -> Array:
	return _strokes.duplicate(true)


func can_undo() -> bool:
	return not _undo_stack.is_empty() or not _active_stroke.is_empty() or not _erased.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty() and _pointer_kind == 0


func undo() -> void:
	_finish_gesture()
	if _undo_stack.is_empty():
		return
	var action: Dictionary = _undo_stack.pop_back()
	var added: Array = action.added
	var removed: Array = action.removed
	for i in range(added.size() - 1, -1, -1):
		_remove_stroke(int(added[i].index))
	for i in range(removed.size() - 1, -1, -1):
		_insert_stroke(int(removed[i].index), removed[i].stroke)
	_redo_stack.append(action)
	queue_redraw()
	strokes_changed.emit()


func redo() -> void:
	_finish_gesture()
	if _redo_stack.is_empty():
		return
	var action: Dictionary = _redo_stack.pop_back()
	for removed in action.removed:
		_remove_stroke(int(removed.index))
	for added in action.added:
		_insert_stroke(int(added.index), added.stroke)
	_undo_stack.append(action)
	queue_redraw()
	strokes_changed.emit()


func clear_canvas() -> void:
	_finish_gesture()
	if _strokes.is_empty():
		return
	var removed: Array[Dictionary] = []
	for i in range(_strokes.size() - 1, -1, -1):
		removed.append({"index": i, "stroke": _strokes[i]})
	_strokes.clear()
	_point_count = 0
	_commit_action({"added": [], "removed": removed})


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	for stroke in _strokes:
		var color := Color.html(stroke.color)
		var width: float = maxf(0.5, float(stroke.width) * size.x / REFERENCE_WIDTH)
		var points := PackedVector2Array()
		for point in stroke.points:
			points.append(Vector2(float(point[0]), float(point[1])) * size)
		if points.size() > 1:
			draw_polyline(points, color, width, true)
		# Round caps also make a click or short tap visible.
		draw_circle(points[0], width * 0.5, color, true, -1.0, true)
		if points.size() > 1:
			draw_circle(points[-1], width * 0.5, color, true, -1.0, true)


func _gui_input(event: InputEvent) -> void:
	if not editable or event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _pointer_kind == 0:
			_start_gesture(event.position, 1)
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		if _pointer_kind == 0:
			_touch_index = event.index
			_start_gesture(event.position, 2)
		accept_event()


func _input(event: InputEvent) -> void:
	if _pointer_kind == 0 or not editable or event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	# Continue the captured pointer outside this Control, including its release.
	var local_event := make_input_local(event)
	if _pointer_kind == 1:
		if local_event is InputEventMouseMotion:
			# Recover if the OS swallowed a release beyond the game window.
			if not local_event.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_finish_gesture()
				return
			_move_gesture(local_event.position)
			get_viewport().set_input_as_handled()
		elif local_event is InputEventMouseButton and local_event.button_index == MOUSE_BUTTON_LEFT and not local_event.pressed:
			_move_gesture(local_event.position, true)
			_finish_gesture()
			get_viewport().set_input_as_handled()
	elif _pointer_kind == 2:
		if local_event is InputEventScreenDrag and local_event.index == _touch_index:
			_move_gesture(local_event.position)
			get_viewport().set_input_as_handled()
		elif local_event is InputEventScreenTouch and local_event.index == _touch_index and not local_event.pressed:
			_move_gesture(local_event.position, true)
			_finish_gesture()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_finish_gesture()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_finish_gesture()


func _start_gesture(point: Vector2, kind: int) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if not eraser and (_strokes.size() >= MAX_STROKES or _point_count >= MAX_POINTS):
		return
	_pointer_kind = kind
	_last_position = _clamp_position(point)
	if eraser:
		_erase_between(_last_position, _last_position)
	else:
		var width := clampf(brush_width, 1.0, 64.0) if is_finite(brush_width) else 4.0
		_active_stroke = {"points": [_normalized(_last_position)], "color": "#" + ink_color.to_html(true), "width": width}
		_strokes.append(_active_stroke)
		_point_count += 1
	queue_redraw()


func _move_gesture(point: Vector2, final_point := false) -> void:
	var local_point := _clamp_position(point)
	if eraser:
		_erase_between(_last_position, local_point)
	elif not _active_stroke.is_empty() and _point_count < MAX_POINTS:
		var distance := local_point.distance_squared_to(_last_position)
		if distance > 0.0001 and (final_point or distance >= 0.64):
			_active_stroke.points.append(_normalized(local_point))
			_point_count += 1
			_last_position = local_point
			queue_redraw()
		return
	_last_position = local_point


func _finish_gesture() -> void:
	if _pointer_kind == 0:
		return
	var added: Array[Dictionary] = []
	if not _active_stroke.is_empty():
		added.append({"index": _strokes.size() - 1, "stroke": _active_stroke})
	var removed := _erased
	_reset_gesture()
	if not added.is_empty() or not removed.is_empty():
		_commit_action({"added": added, "removed": removed})


func _reset_gesture() -> void:
	_pointer_kind = 0
	_touch_index = -1
	_active_stroke = {}
	_erased = []


func _erase_between(from: Vector2, to: Vector2) -> void:
	var safe_width := clampf(brush_width, 1.0, 64.0) if is_finite(brush_width) else 4.0
	var eraser_radius := maxf(8.0, safe_width * 1.6) * size.x / REFERENCE_WIDTH
	for i in range(_strokes.size() - 1, -1, -1):
		var stroke: Dictionary = _strokes[i]
		var threshold: float = eraser_radius + float(stroke.width) * size.x / REFERENCE_WIDTH * 0.5
		var points: Array = stroke.points
		var previous := Vector2(float(points[0][0]), float(points[0][1])) * size
		var hit := _point_segment_distance_squared(previous, from, to) <= threshold * threshold
		for j in range(1, points.size()):
			if hit:
				break
			var current := Vector2(float(points[j][0]), float(points[j][1])) * size
			hit = _segment_distance_squared(from, to, previous, current) <= threshold * threshold
			previous = current
		if hit:
			_erased.append({"index": i, "stroke": stroke})
			_remove_stroke(i)
	queue_redraw()


func _commit_action(action: Dictionary) -> void:
	_redo_stack.clear()
	_undo_stack.append(action)
	var history_points := 0
	for entry in _undo_stack:
		history_points += _action_point_count(entry)
	while _undo_stack.size() > 1 and (_undo_stack.size() > MAX_HISTORY_ACTIONS or history_points > MAX_HISTORY_POINTS):
		history_points -= _action_point_count(_undo_stack.pop_front())
	queue_redraw()
	strokes_changed.emit()


func _insert_stroke(index: int, stroke: Dictionary) -> void:
	_strokes.insert(index, stroke)
	_point_count += stroke.points.size()


func _remove_stroke(index: int) -> void:
	_point_count -= _strokes[index].points.size()
	_strokes.remove_at(index)


func _normalized(point: Vector2) -> Array:
	return [point.x / maxf(size.x, 1.0), point.y / maxf(size.y, 1.0)]


func _clamp_position(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, 0.0, size.x), clampf(point.y, 0.0, size.y))


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _action_point_count(action: Dictionary) -> int:
	var total := 0
	for entry in action.added:
		total += entry.stroke.points.size()
	for entry in action.removed:
		total += entry.stroke.points.size()
	return total


func _point_segment_distance_squared(point: Vector2, from: Vector2, to: Vector2) -> float:
	var direction := to - from
	if direction.length_squared() < 0.000001:
		return point.distance_squared_to(from)
	var weight := clampf((point - from).dot(direction) / direction.length_squared(), 0.0, 1.0)
	return point.distance_squared_to(from + direction * weight)


func _segment_distance_squared(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return 0.0
	return minf(minf(_point_segment_distance_squared(a, c, d), _point_segment_distance_squared(b, c, d)), minf(_point_segment_distance_squared(c, a, b), _point_segment_distance_squared(d, a, b)))
