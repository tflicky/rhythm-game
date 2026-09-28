shader_type canvas_item;
// Recolours only the grey (low-saturation, not-black) pixels -- e.g. the metal
// tongs -- and leaves everything else (the brown patty, black outlines) alone.
// `layer` can also keep just one part of the drawing, so the tongs and the patty
// can be drawn by separate sprites: 0 = everything, 1 = grey/black only (tongs),
// 2 = coloured only (patty).

uniform vec4 tint : source_color = vec4(0.25, 0.55, 0.95, 1.0);
uniform bool use_tint = true;
uniform int layer = 0;
uniform float grey_tolerance = 0.12;   // how close to grey a pixel must be
uniform float min_brightness = 0.2;    // darker than this counts as outline

void fragment() {
	vec4 c = COLOR;   // already texture x modulate in Godot 4
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	bool grey = mx - mn < grey_tolerance;
	if ((layer == 1 && !grey) || (layer == 2 && grey)) {
		c.a = 0.0;
	}
	if (use_tint && grey && mx > min_brightness) {
		c.rgb = tint.rgb * (0.45 + 0.75 * mx);   // keep the shading of the grey
	}
	COLOR = c;
}
