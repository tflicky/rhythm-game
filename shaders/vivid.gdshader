shader_type canvas_item;
// Full-screen colour pop for a whole level: draws over the art (below the UI) and
// re-colours what's already on screen. Makes colours richer without making the
// picture washed out -- "a kid seeing the world" on a sunny day.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float vibrance = 0.5;     // extra colour, strongest on dull/greyish colours
uniform float saturation = 1.1;   // extra colour on everything
uniform float contrast = 0.0;     // gentle S-curve so colours read clean, 0 = none
uniform float light = 1.2;        // sunshine: lifts the midtones, white stays white, 1 = none

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	float amount = saturation * (1.0 + vibrance * (1.0 - sat));
	c = mix(vec3(luma), c, amount);
	c = clamp(c, 0.0, 1.0);
	c = mix(c, c * c * (3.0 - 2.0 * c), contrast);   // S-curve around the midtones
	c = pow(c, vec3(1.0 / light));
	COLOR = vec4(c, 1.0);
}
