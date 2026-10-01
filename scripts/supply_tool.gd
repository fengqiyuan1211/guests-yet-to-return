extends Node2D
## Reusable 2D prop. A later bartending controller drives operations and stock.

@export var tool_id := ""
@export var supports_open := false
@export var liquid_shape := PackedVector2Array()
var fill_ratio := 0.0
var is_open := false
var _closed_positions: Dictionary = {}
var _lid_tween: Tween
var _shake_tween: Tween

func _ready() -> void:
	for part_name in ["StrainerTop", "Cap"]:
		var part := get_node_or_null(part_name) as Node2D
		if part != null:
			_closed_positions[part_name] = part.position
	set_fill_ratio(0.0)

func set_open(value: bool, animated := true) -> void:
	if not supports_open:
		return
	is_open = value
	if is_instance_valid(_lid_tween):
		_lid_tween.kill()
	if animated:
		_lid_tween = create_tween().set_parallel(true)
	for part_name in _closed_positions:
		var part: Node2D = get_node(part_name)
		var offset := Vector2(145, -4) if part_name == "StrainerTop" else Vector2(165, -24)
		var destination: Vector2 = _closed_positions[part_name] + (offset if value else Vector2.ZERO)
		var angle := deg_to_rad(16.0 if value else 0.0)
		if animated:
			_lid_tween.tween_property(part, "position", destination, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_lid_tween.tween_property(part, "rotation", angle, 0.25)
		else:
			part.position = destination
			part.rotation = angle

func set_fill_ratio(value: float, color := Color("c98537")) -> void:
	fill_ratio = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
	var fill := get_node_or_null("Liquid") as Polygon2D
	if fill == null or liquid_shape.is_empty():
		return
	fill.color = color
	fill.visible = fill_ratio > 0.0
	if not fill.visible:
		return
	var minimum_y := INF
	var maximum_y := -INF
	for point in liquid_shape:
		minimum_y = minf(minimum_y, point.y)
		maximum_y = maxf(maximum_y, point.y)
	var line_y := lerpf(maximum_y, minimum_y, fill_ratio)
	# Clip the liquid interior against a horizontal fill level; leave glass pixels intact.
	var clipped := PackedVector2Array()
	var previous: Vector2 = liquid_shape[liquid_shape.size() - 1]
	for point in liquid_shape:
		var inside := point.y >= line_y
		var previous_inside := previous.y >= line_y
		if inside != previous_inside:
			var weight := (line_y - previous.y) / (point.y - previous.y)
			clipped.append(previous.lerp(point, weight))
		if inside:
			clipped.append(point)
		previous = point
	fill.polygon = clipped

func drag_to(world_position: Vector2) -> void:
	global_position = world_position

func set_tilt(degrees: float) -> void:
	rotation_degrees = degrees

func animate_shake() -> void:
	if supports_open and is_open:
		return
	if is_instance_valid(_shake_tween):
		_shake_tween.kill()
	var original_angle := rotation
	_shake_tween = create_tween()
	for i in range(4):
		_shake_tween.tween_property(self, "rotation", original_angle + deg_to_rad(13), 0.07)
		_shake_tween.tween_property(self, "rotation", original_angle - deg_to_rad(13), 0.07)
	_shake_tween.tween_property(self, "rotation", original_angle, 0.08)

func get_anchor(anchor_name: String) -> Vector2:
	var anchor := get_node_or_null(anchor_name) as Marker2D
	return anchor.global_position if anchor != null else global_position

func _exit_tree() -> void:
	if is_instance_valid(_lid_tween):
		_lid_tween.kill()
	if is_instance_valid(_shake_tween):
		_shake_tween.kill()
