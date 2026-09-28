shader_type canvas_item;
// Recolours only the grey (low-saturation, not-black) pixels -- e.g. the metal
// tongs -- and leaves everything else (the brown patty, black outlines) alone.

uniform vec4 tint : source_color = vec4(0.25, 0.55, 0.95, 1.0);
uniform float grey_tolerance = 0.12;   // how close to grey a pixel must be
uniform float min_brightness = 0.2;    // darker than this counts as outline

void fragment() {
	vec4 c = COLOR;   // already texture x modulate in Godot 4
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	if (mx - mn < grey_tolerance && mx > min_brightness) {
		c.rgb = tint.rgb * (0.45 + 0.75 * mx);   // keep the shading of the grey
	}
	COLOR = c;
}
