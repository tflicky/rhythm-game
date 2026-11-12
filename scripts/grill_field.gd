@tool
extends Node2D
## Placeholder backdrop for the grill scenes: a plain green field seen from the
## same high three-quarter angle as the grill and picnic table. The horizon sits
## near the top, the grass fades lighter into the distance, tufts shrink toward
## the horizon, and soft shadows sit under the table, bench and grill so they
## stand on the ground. Drawn in code -- replace with real art whenever.
## Visible in the editor too (@tool), so you can drag the shadows into place.

@export var size := Vector2(1152, 648):
	set(v): size = v; queue_redraw()
## Screen y of the horizon. Higher up = looking more steeply down.
@export var horizon_y := 96.0:
	set(v): horizon_y = v; queue_redraw()
@export var sky_top := Color(0.62, 0.82, 0.95):
	set(v): sky_top = v; queue_redraw()
@export var sky_bottom := Color(0.86, 0.94, 0.98):
	set(v): sky_bottom = v; queue_redraw()
@export var grass_far := Color(0.62, 0.8, 0.45):
	set(v): grass_far = v; queue_redraw()
@export var grass_near := Color(0.36, 0.64, 0.27):
	set(v): grass_near = v; queue_redraw()
@export var tuft_count := 90:
	set(v): tuft_count = v; queue_redraw()
## Soft ground shadows: each is Rect2(centre x, centre y, width, height) on screen.
## Defaults sit under the picnic table, its bench, and the grill's legs.
@export var shadows: Array[Rect2] = [
	Rect2(232, 352, 330, 64),   # table
	Rect2(120, 410, 230, 40),   # bench
	Rect2(670, 560, 400, 92),   # grill
]:
	set(v): shadows = v; queue_redraw()
@export var shadow_color := Color(0.12, 0.3, 0.1, 0.28):
	set(v): shadow_color = v; queue_redraw()


func _draw() -> void:
	# sky: a thin band above the horizon
	_vgradient(0.0, horizon_y, sky_top, sky_bottom)
	# a faint, bushy tree line along the horizon so the field reads as far away
	var trees := grass_far.darkened(0.3).lerp(sky_bottom, 0.4)
	for i in 48:
		var x := size.x * i / 47.0
		var r := 9.0 + 5.0 * absf(sin(i * 1.7)) + 3.0 * absf(sin(i * 0.6))
		draw_circle(Vector2(x, horizon_y - r * 0.45), r, trees)
	# grass: lighter and hazier far away, richer up close
	_vgradient(horizon_y, size.y, grass_far, grass_near, 24)
	# soft shadows under the furniture (stacked ellipses fake a blur)
	for s in shadows:
		for k in 4:
			var f := 1.0 - k * 0.18
			_ellipse(Vector2(s.position.x, s.position.y), Vector2(s.size.x, s.size.y) * 0.5 * f,
				Color(shadow_color, shadow_color.a * 0.35))
	# tufts: a few blades each, smaller and paler toward the horizon
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in tuft_count:
		var d := pow(rng.randf(), 0.7)               # 0 = horizon, 1 = bottom edge
		var y := lerpf(horizon_y + 6.0, size.y + 10.0, d)
		var x := rng.randf_range(-10.0, size.x + 10.0)
		var s := lerpf(0.35, 1.3, d)                 # perspective: near tufts are bigger
		var col := grass_far.lerp(grass_near, d).darkened(0.18 + rng.randf() * 0.1)
		for b in 3:
			var base := Vector2(x + (b - 1) * 4.0 * s, y)
			var tip := base + Vector2((b - 1) * 5.0 * s + rng.randf_range(-2, 2), -rng.randf_range(9.0, 15.0) * s)
			draw_line(base, tip, col, maxf(1.0, 2.2 * s), true)


func _vgradient(y0: float, y1: float, top: Color, bottom: Color, steps := 12) -> void:
	for i in steps:
		var a := lerpf(y0, y1, float(i) / steps)
		var b := lerpf(y0, y1, float(i + 1) / steps)
		draw_rect(Rect2(0, floorf(a), size.x, ceilf(b) - floorf(a) + 1.0), top.lerp(bottom, (i + 0.5) / steps))


func _ellipse(c: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	draw_colored_polygon(pts, col)
