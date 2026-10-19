shader_type canvas_item;
render_mode unshaded;
uniform float clock = 0.0;
uniform float motion = 1.0;
uniform bool ocean = true;
void fragment() {
	vec2 uv=UV;
	vec4 source=texture(TEXTURE,uv);
	// Conservative new coastline: island occupies left upper half; boat remains still.
	float water=step(.67,uv.y);
	water*=1.0-step(.81,uv.x)*step(uv.y,.73);
	float tick=floor(clock*7.0)*motion;
	vec2 cell=floor(uv*vec2(320.0,180.0));
	float ripple=step(.87,fract(sin(dot(cell+vec2(tick,0),vec2(13.1,7.7)))*4375.0));
	float band=step(.7,sin(cell.y*.45-tick*.18));
	vec3 color=source.rgb;
	if(ocean) color+=vec3(.035,.045,.048)*ripple*band*water*motion;
	COLOR=vec4(color,source.a);
}
