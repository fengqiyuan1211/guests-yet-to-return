extends TextureRect
## Matched background paintings blend continuously; UI is never darkened.
var light_weights := Vector3.ZERO
var guests: Node2D

func _ready() -> void:
	var blend := ShaderMaterial.new()
	blend.shader = preload("res://shaders/pixel_day_night.gdshader")
	texture=load(preload("res://scripts/saloon_composition.gd").BACKGROUND_PATH)
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	material = blend
	guests = get_node("../Stage/GuestLayer")
	_process(0.0)

func weights_at(minute: float) -> Vector3:
	# x=day, y=night, z=dawn; sunset is the remaining weight.
	# Smoothstep gives zero slope at every transition endpoint, including midnight.
	var hour := fposmod(minute, 1440.0) / 60.0
	if hour < 4.0 or hour >= 21.0:
		return Vector3(0.0, 1.0, 0.0)
	if hour < 5.5:
		var dawn := smoothstep(4.0, 5.5, hour)
		return Vector3(0.0, 1.0 - dawn, dawn)
	if hour < 6.5:
		return Vector3(0.0, 0.0, 1.0)
	if hour < 8.0:
		var morning := smoothstep(6.5, 8.0, hour)
		return Vector3(morning, 0.0, 1.0 - morning)
	if hour < 16.0:
		return Vector3(1.0, 0.0, 0.0)
	if hour < 18.0:
		return Vector3(1.0 - smoothstep(16.0, 18.0, hour), 0.0, 0.0)
	if hour < 19.0:
		return Vector3.ZERO
	return Vector3(0.0, smoothstep(19.0, 21.0, hour), 0.0)

func _process(_delta: float) -> void:
	light_weights = weights_at(TimeManager.visual_minutes())
	material.set_shader_parameter("day_weight", light_weights.x)
	material.set_shader_parameter("night_weight", light_weights.y)
	material.set_shader_parameter("dawn_weight", light_weights.z)
	var dusk := Color(1.0, 0.96, 0.90)
	var tint := dusk.lerp(Color(1.0, 1.0, 0.98), light_weights.x)
	tint = tint.lerp(Color(0.88, 0.91, 1.0), light_weights.y)
	tint = tint.lerp(Color(0.93, 0.90, 0.99), light_weights.z)
	guests.modulate = tint
