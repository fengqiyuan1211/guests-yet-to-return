shader_type canvas_item;
render_mode unshaded;
uniform float clock = 0.0;
uniform float motion = 1.0;
uniform bool ocean = true;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
float cut_box(vec2 uv,vec4 box) {
	return smoothstep(box.x-.005,box.x,uv.x)*(1.0-smoothstep(box.z,box.z+.005,uv.x))*smoothstep(box.y-.006,box.y,uv.y)*(1.0-smoothstep(box.w,box.w+.006,uv.y));
}
float water(vec2 uv) {
	// Coastline and the foreground jetty are stable. Conservative masks also cover posts/ropes.
	float top=mix(.476,.510,smoothstep(.54,.72,uv.x));
	float bottom=1.06;
	if(uv.x>.34) bottom=mix(1.02,.78,clamp((uv.x-.34)/.42,0.0,1.0));
	if(uv.x>.76) bottom=mix(.77,.58,clamp((uv.x-.76)/.20,0.0,1.0));
	float mask=smoothstep(top,top+.012,uv.y)*(1.0-smoothstep(bottom-.014,bottom,uv.y));
	mask*=1.0-cut_box(uv,vec4(.537,.751,.605,.945));
	mask*=1.0-cut_box(uv,vec4(.614,.815,.657,.922));
	mask*=1.0-cut_box(uv,vec4(.731,.589,.784,.865));
	mask*=1.0-cut_box(uv,vec4(.803,.673,.836,.783));
	mask*=1.0-cut_box(uv,vec4(.908,.563,1.0,1.0));
	return mask;
}
void fragment() {
	vec2 uv=UV;
	float t=clock*motion;
	vec4 base=texture(TEXTURE,uv);
	float mask=ocean ? water(uv) : 0.0;
	float depth=clamp((uv.y-.47)/.53,0.0,1.0);
	// Three travelling wave scales, with perspective and slow irregular modulation.
	float phase=uv.y*(95.0-50.0*depth)-t*1.25+sin(uv.x*21.0+t*.19);
	float swell=sin(phase)+.38*sin(phase*1.83+t*.37+uv.x*34.0);
	float cross=sin(uv.x*36.0+uv.y*16.0-t*.48);
	float rough=noise(vec2(uv.x*80.0+t*.25,uv.y*120.0-t*.32))-.5;
	vec2 offset=vec2(cross*.0018+swell*.0008,swell*.0018+rough*.0015)*(0.18+depth)*motion;
	vec4 moved=texture(TEXTURE,uv+offset*mask);
	vec3 col=mix(base.rgb,moved.rgb,mask);
	float ridge=pow(max(0.0,sin(phase+rough*1.8)),12.0);
	float breakup=noise(vec2(uv.x*125.0+t*.3,uv.y*75.0));
	float reflection=exp(-pow((uv.x-.523)/(0.018+depth*.12),2.0));
	col+=vec3(1.0,.71,.34)*reflection*ridge*breakup*.14*mask*motion;
	float foam=ridge*smoothstep(.65,.88,breakup)*depth;
	col=mix(col,vec3(.72,.85,.81),foam*.065*mask*motion);
	// Local flame flicker; no rings or circular geometry on the illustration.
	float lamp=exp(-dot((uv-vec2(.881,.733))*vec2(80,55),(uv-vec2(.881,.733))*vec2(80,55)));
	col+=vec3(.09,.045,.008)*lamp*(.5+.5*sin(t*1.8)+.15*sin(t*4.1))*motion;
	COLOR=vec4(col,base.a);
}
