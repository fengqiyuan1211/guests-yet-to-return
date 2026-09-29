shader_type canvas_item;
render_mode unshaded;
uniform sampler2D day_texture : source_color;
uniform sampler2D night_texture : source_color;
uniform sampler2D dawn_texture : source_color;
uniform float dawn_weight = 0.0;
uniform float day_weight = 0.0;
uniform float night_weight = 0.0;
void fragment() {
	vec4 sunset = texture(TEXTURE, UV);
	vec4 daylight = texture(day_texture, UV);
	vec4 night = texture(night_texture, UV);
	COLOR = sunset * max(0.0, 1.0 - day_weight - night_weight - dawn_weight)
		+ daylight * day_weight + night * night_weight
		+ texture(dawn_texture, UV) * dawn_weight;
}
