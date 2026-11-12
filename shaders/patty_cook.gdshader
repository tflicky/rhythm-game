shader_type canvas_item;
// How cooked the patty looks. Only touches coloured (non-grey) pixels, so on a
// drawing of tongs + patty the metal tongs and black outlines stay as they are.
// raw = 1: pink raw meat (no sear marks); raw = 0: the drawing as painted (browned).

uniform float raw : hint_range(0.0, 1.0) = 0.0;
uniform vec3 raw_color : source_color = vec3(0.93, 0.45, 0.47);
uniform float grey_tolerance = 0.12;

void fragment() {
	vec4 c = COLOR;
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	if (raw > 0.0 && mx - mn >= grey_tolerance) {
		float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
		// the main brown goes full pink, sear marks mostly fade, dark edges stay darker
		float k = smoothstep(0.04, 0.2, l);
		vec3 pink = raw_color * mix(0.4, 1.0, k) * mix(1.0, 0.92 + 0.3 * l, k);
		c.rgb = mix(c.rgb, clamp(pink, 0.0, 1.0), raw);
	}
	COLOR = c;
}
