extends "res://scripts/harbor_day_night.gd"
## Same clock weights and blend shader as the saloon/harbor, independent counter art.
func _ready() -> void:
	expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode=TextureRect.STRETCH_SCALE
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture=preload("res://scripts/pixel_art.gd").texture("res://assets/workbench/background.png")
	var blend:=ShaderMaterial.new()
	blend.shader=preload("res://shaders/pixel_day_night.gdshader")
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	material=blend
	update_lighting(TimeManager.visual_minutes())
	set_process(true)
