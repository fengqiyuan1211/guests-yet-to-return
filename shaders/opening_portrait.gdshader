shader_type canvas_item;
render_mode unshaded;
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
}

// Ignore the low-alpha extraction fringe; do not add a portrait glow.
// Keep CanvasItem modulation so the brief entrance dissolve still works.
void fragment() {
	vec4 portrait = texture(TEXTURE, UV);
	portrait.a = step(0.75, portrait.a);
	COLOR = portrait * item_tint;
}
