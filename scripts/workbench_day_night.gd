extends "res://scripts/harbor_day_night.gd"
## Same clock weights and blend shader as the saloon/harbor, independent counter art.
func _ready() -> void:
	expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode=TextureRect.STRETCH_SCALE
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture=preload("res://assets/workbench/background.png")
	var blend:=ShaderMaterial.new()
	blend.shader=preload("res://assets/art/day_night.gdshader")
	blend.set_shader_parameter("day_texture",_painting("res://assets/workbench/background-day-v1.png",texture))
	blend.set_shader_parameter("night_texture",_painting("res://assets/workbench/background-night-v1.png",texture))
	blend.set_shader_parameter("dawn_texture",_painting("res://assets/workbench/background-dawn-v1.png",texture))
	material=blend
	update_lighting(TimeManager.visual_minutes())
	set_process(true)
