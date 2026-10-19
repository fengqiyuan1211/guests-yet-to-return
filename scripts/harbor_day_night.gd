extends "res://scripts/day_night_background.gd"
## The harbor shares the tavern's clock curve, but uses its own matched paintings.

const DAY_PATH := "res://assets/art/shop/harbor-shop-day.png"
const DUSK_PATH := "res://assets/art/shop/harbor-shop-dusk.png"
const NIGHT_PATH := "res://assets/art/shop/harbor-shop-night.png"
const DAWN_PATH := "res://assets/art/shop/harbor-shop-dawn.png"

var ambient_tint := Color.WHITE


func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# All paintings and the counter sample the same normalized scene coordinates.
	# Their file dimensions may differ without moving the shelving or countertop.
	stretch_mode = TextureRect.STRETCH_SCALE
	var daylight := _painting(DAY_PATH)
	texture = _painting(DUSK_PATH, daylight)
	var blend := ShaderMaterial.new()
	blend.shader = preload("res://shaders/pixel_day_night.gdshader")
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	material = blend
	# The shop updates this first, then tints its portraits and objects in one frame.
	set_process(false)
	update_lighting(TimeManager.visual_minutes())


func _painting(path: String, fallback: Texture2D = null) -> Texture2D:
	return preload("res://scripts/pixel_art.gd").texture(path) if ResourceLoader.exists(path) else fallback


func update_lighting(minute: float) -> void:
	# weights_at() is inherited from the tavern rather than keeping a second curve.
	light_weights = weights_at(minute)
	material.set_shader_parameter("day_weight", light_weights.x)
	material.set_shader_parameter("night_weight", light_weights.y)
	material.set_shader_parameter("dawn_weight", light_weights.z)
	var dusk_weight := maxf(0.0, 1.0 - light_weights.x - light_weights.y - light_weights.z)
	ambient_tint = Color(1.0, 0.96, 0.90) * dusk_weight \
		+ Color(1.0, 1.0, 0.98) * light_weights.x \
		+ Color(0.88, 0.91, 1.0) * light_weights.y \
		+ Color(0.93, 0.90, 0.99) * light_weights.z


func _process(_delta: float) -> void:
	update_lighting(TimeManager.visual_minutes())
