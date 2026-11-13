shader_type canvas_item;
// How cooked the patty looks. Only touches coloured (non-grey) pixels, so on a
// drawing of tongs + patty the metal tongs and black outlines stay as they are.
// raw = 1: pink raw meat (no sear marks); raw = 0: the drawing as painted (browned).

uniform float raw : hint_range(0.0, 1.0) = 0.0;
uniform vec3 raw_color : source_color = vec3(0.93, 0.45, 0.47);
uniform float grey_tolerance = 0.12;
// A dark outline around the whole drawing so the grey tongs stand out from the
// grass and the table. Width in texture pixels (0 = none).
uniform float outline_width = 5.0;
uniform vec4 outline_color : source_color = vec4(0.12, 0.08, 0.07, 0.9);

void fragment() {
	vec4 c = COLOR;
	bool edge = false;
	if (outline_width > 0.0 && c.a < 0.5) {
		// a see-through pixel next to the drawing becomes outline
		float near = 0.0;
		for (int i = 0; i < 12; i++) {
			float a = 6.2831853 * float(i) / 12.0;
			vec2 d = vec2(cos(a), sin(a)) * TEXTURE_PIXEL_SIZE;
			near = max(near, texture(TEXTURE, UV + d * outline_width).a);
			near = max(near, texture(TEXTURE, UV + d * outline_width * 0.5).a);
		}
		if (near > 0.5) {
			c = mix(vec4(outline_color.rgb, outline_color.a * near), c, c.a);
			edge = true;
		}
	}
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	if (!edge && raw > 0.0 && mx - mn >= grey_tolerance) {
		float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
		// the main brown goes full pink, sear marks mostly fade, dark edges stay darker
		float k = smoothstep(0.04, 0.2, l);
		vec3 pink = raw_color * mix(0.4, 1.0, k) * mix(1.0, 0.92 + 0.3 * l, k);
		c.rgb = mix(c.rgb, clamp(pink, 0.0, 1.0), raw);
	}
	COLOR = c;
}
