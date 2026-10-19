extends TextureRect
## This scene uses a dedicated water-only material. UI and land remain undeformed.
var elapsed := 0.0
var waves := true
var playback_speed := 1.0
func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode=TextureRect.STRETCH_SCALE
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var shader_material:=ShaderMaterial.new()
	shader_material.shader=preload("res://shaders/pixel_ocean.gdshader")
	shader_material.set_shader_parameter("ocean",waves)
	material=shader_material
func _process(delta: float) -> void:
	if not get_window().has_focus(): return
	if not OpeningFlow.reduced_motion: elapsed+=minf(delta,.05)*playback_speed
	material.set_shader_parameter("clock",elapsed)
	material.set_shader_parameter("motion",0.0 if OpeningFlow.reduced_motion else 1.0)
