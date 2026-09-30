shader_type canvas_item;
uniform float fade : hint_range(0.0, 1.0) = 0.88;
void fragment() {
	float luminance = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	COLOR.rgb = mix(COLOR.rgb, vec3(luminance) * vec3(0.94, 0.88, 0.78), fade);
}
