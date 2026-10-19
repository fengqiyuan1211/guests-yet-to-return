shader_type canvas_item;
render_mode unshaded;
// Same time weights as the original saloon. One geometry avoids scenery jumping.
uniform float day_weight = 0.0;
uniform float night_weight = 0.0;
uniform float dawn_weight = 0.0;
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec3 tint = vec3(1.0);
	tint = mix(tint, vec3(1.04,1.03,.98), day_weight);
	tint = mix(tint, vec3(.60,.66,.91), night_weight);
	tint = mix(tint, vec3(.86,.78,.95), dawn_weight);
	// Keep painted lamps bright while shadows cool at night.
	float lamp = step(.82,source.r)*step(source.b,source.r*.55)*step(.54,source.g);
	COLOR = vec4(mix(source.rgb*tint,source.rgb,lamp*.75*night_weight),source.a);
}
