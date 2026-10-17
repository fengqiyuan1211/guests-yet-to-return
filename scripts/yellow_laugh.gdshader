shader_type canvas_item;
uniform float clock = 0.0;
uniform float energy = 0.5;
void vertex(){
 vec2 p=VERTEX;
 float y=p.y/870.0;
 float anchor=1.0-smoothstep(0.70,0.96,y);
 float slow=sin(clock*6.283185/2.0);
 float beat=sin(clock*6.283185*4.5);
 float second=sin(clock*6.283185*9.0+0.7);
 float gain=0.30+0.70*energy;
 // Feet stay planted while the shoulders compress with each laugh.
 p.y+=(7.0*slow+5.5*beat*gain+1.3*second*gain)*anchor;
 p.x+=(8.0*slow+2.2*beat*gain)*anchor;
 float belly=exp(-pow((y-0.60)/0.19,2.0));
 p.x+=(p.x-300.0)*0.024*belly*beat*gain;
 float head=1.0-smoothstep(0.30,0.48,y);
 float angle=(0.018*slow+0.010*beat*gain)*head;
 vec2 q=p-vec2(285.0,420.0);
 p=vec2(cos(angle)*q.x-sin(angle)*q.y,sin(angle)*q.x+cos(angle)*q.y)+vec2(285.0,420.0);
 // Subtle mouth compression instead of switching to another face.
 vec2 mouth=(VERTEX-vec2(183.0,244.0))/vec2(87.0,73.0);
 float mask=exp(-dot(mouth,mouth)*2.0);
 p.y+=(VERTEX.y-244.0)*0.11*beat*gain*mask;
 VERTEX=p;
}
