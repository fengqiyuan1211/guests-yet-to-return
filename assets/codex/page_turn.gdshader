shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D paper_texture : source_color;

// A moving fold: the printed face, the curved blank reverse, then its cast shadow.
// Reverse the same motion to place the preceding leaf back onto the journal.
void fragment() {
	vec2 uv = UV;
	float lift = sin(progress * 3.14159265);
	float fold = 1.02 - progress * 1.30 + (0.5 - uv.y) * lift * 0.13;
	float radius = 0.115 * lift;
	float d = uv.x - fold;
	vec4 result = vec4(0.0);
	if (d <= 0.0) {
		vec2 front_uv = uv;
		front_uv.x += radius * 0.06 * exp(d * 35.0);
		result = texture(TEXTURE, front_uv);
		result.rgb *= 1.0 - 0.19 * lift * exp(d * 36.0);
	} else if (radius > 0.001 && d < radius) {
		float arc = d / radius;
		vec2 back_uv = vec2(clamp(fold - asin(arc) * radius, 0.0, 1.0), uv.y);
		result = texture(paper_texture, back_uv);
		result.rgb *= 0.80 + 0.27 * sin(arc * 3.14159265);
		result.a *= 1.0 - smoothstep(0.96, 1.0, arc);
	} else if (radius > 0.001) {
		float shadow_distance = d - radius;
		result = vec4(0.12, 0.055, 0.02, 0.34 * lift * exp(-shadow_distance * 65.0));
	}
	COLOR = result;
}
