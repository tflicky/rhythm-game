@tool
extends Node2D
## Placeholder backdrop for the grill scenes: a plain green field seen from the
## same high three-quarter angle as the grill and picnic table. The horizon sits
## near the top, the grass fades lighter into the distance, tufts shrink toward
## the horizon, and soft shadows sit under the table, bench and grill so they
## stand on the ground. Your art takes over where it exists: grass tufts
## (art/grilling/scene/grass.png), a bush (bush.png, small and repeated as the
## line along the horizon), and a football that gets
## thrown across the background once mid-song (football.png) -- like the
## monkey level's surfer cameo.
## Visible in the editor too (@tool), so you can drag the shadows into place.

const ART_DIR := "res://art/grilling/scene/"

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
@export var tuft_count := 70:
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
## Shaped shadows: each is the outline of a flat top (tabletop, bench seat) as
## it sits on screen, dropped straight down onto the grass by `shadow_drops`
## (the leg height there) -- so the shadow sits right under it, like a high sun.
@export var shadow_shapes: Array[PackedVector2Array] = []:
	set(v): shadow_shapes = v; queue_redraw()
@export var shadow_drops: PackedVector2Array = []:
	set(v): shadow_drops = v; queue_redraw()
@export var shape_shadow_color := Color(0.08, 0.22, 0.06, 0.5):
	set(v): shape_shadow_color = v; queue_redraw()

@export_group("Your art")
## Your grass tuft, scattered over the field (smaller toward the horizon).
@export var art_grass: Texture2D:
	set(v): art_grass = v; queue_redraw()
@export var grass_scale_far := 0.05:      ## tuft size at the horizon (1 = as drawn)
	set(v): grass_scale_far = v; queue_redraw()
@export var grass_scale_near := 0.14:     ## tuft size at the bottom edge
	set(v): grass_scale_near = v; queue_redraw()
@export var art_bush: Texture2D:
	set(v): art_bush = v; queue_redraw()
@export var horizon_bush_h := 24.0:      ## height of the little bushes along the horizon
	set(v): horizon_bush_h = v; queue_redraw()
## How far up the bushes (fraction of their height) the solid band behind them reaches.
@export var horizon_band := 0.55:
	set(v): horizon_band = v; queue_redraw()
@export var horizon_band_color := Color(0.03, 0.3, 0.12):
	set(v): horizon_band_color = v; queue_redraw()
@export var horizon_haze := 0.4:         ## 0 = horizon bushes at full colour, 1 = faded into the sky
	set(v): horizon_haze = v; queue_redraw()
## How the tufts spread from horizon to front: 1 = even, higher = more toward the horizon.
@export var grass_spread := 1.6:
	set(v): grass_spread = v; queue_redraw()

@export_group("Football cameo (background, mid-song)")
@export var art_football: Texture2D
## Beat the throw starts and how long it's in the air (beats 79-88 have no cues).
@export var football_beat := 80.0
@export var football_beats := 8.0
@export var football_len := 70.0          ## px nose to tail (it's far away)
@export var football_from := Vector2(-60, 150)   ## off the left edge
@export var football_to := Vector2(1212, 150)    ## off the right edge
@export var football_peak := 125.0        ## how high the arc rises above the line between them
## Set by the game: the throw only happens during the real song, not practice.
var cameo_on := false


func _ready() -> void:
	for slot in [["art_grass", "grass"], ["art_bush", "bush"], ["art_football", "football"]]:
		if get(slot[0]) == null:
			for ext in ["png", "webp"]:
				var path := "%s%s.%s" % [ART_DIR, slot[1], ext]
				if ResourceLoader.exists(path):
					set(slot[0], load(path))
					break


func _process(_dt: float) -> void:
	if not Engine.is_editor_hint() and (_football_k() >= -0.05 and _football_k() <= 1.05):
		queue_redraw()


## 0..1 through the throw, or outside that range when the ball isn't in the air.
func _football_k() -> float:
	if art_football == null or not cameo_on or Conductor.seconds_per_beat <= 0.0:
		return -1.0
	var beat: float = (Conductor.visual_position - Conductor.first_beat_offset) / Conductor.seconds_per_beat
	return (beat - football_beat) / maxf(football_beats, 0.01)


func _draw() -> void:
	# sky: a thin band above the horizon
	_vgradient(0.0, horizon_y, sky_top, sky_bottom)
	# a faint, bushy line along the horizon so the field reads as far away:
	# your bush, small and repeated (or plain circles until bush.png exists)
	if art_bush:
		# a flat, darker-green band along the horizon behind the bushes, so no
		# sky shows through the gaps between them -- the bush tops still poke up
		draw_rect(Rect2(0, horizon_y - horizon_bush_h * horizon_band, size.x, horizon_bush_h * horizon_band + 4.0), horizon_band_color)
		var hr := RandomNumberGenerator.new()
		hr.seed = 7
		var x := -20.0
		while x < size.x + 20.0:
			var h := horizon_bush_h * hr.randf_range(0.75, 1.25)
			var w := h * art_bush.get_width() / art_bush.get_height()
			var fl := 1.0 if hr.randf() < 0.5 else -1.0
			draw_set_transform(Vector2(x, horizon_y + 3.0), 0.0, Vector2(fl, 1.0))
			draw_texture_rect(art_bush, Rect2(-w * 0.5, -h, w, h), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			x += w * hr.randf_range(0.55, 0.8)        # overlap into one line
		# far away = hazy: wash the line toward the sky colour
		draw_rect(Rect2(0, 0, size.x, horizon_y), Color(sky_bottom, horizon_haze))
	else:
		var trees := grass_far.darkened(0.3).lerp(sky_bottom, 0.4)
		for i in 48:
			var x := size.x * i / 47.0
			var r := 9.0 + 5.0 * absf(sin(i * 1.7)) + 3.0 * absf(sin(i * 0.6))
			draw_circle(Vector2(x, horizon_y - r * 0.45), r, trees)
	# grass: lighter and hazier far away, richer up close
	_vgradient(horizon_y, size.y, grass_far, grass_near, 24)
	# shaped shadows: soft edge (a few grown copies, faint) around a darker core
	for i in shadow_shapes.size():
		var drop: Vector2 = shadow_drops[i] if i < shadow_drops.size() else Vector2.ZERO
		var pts: PackedVector2Array = shadow_shapes[i]
		if pts.size() < 3:
			continue
		var c := Vector2.ZERO
		for p in pts:
			c += p
		c /= pts.size()
		for k in 5:
			var grow := 14.0 - k * 3.5        # px: biggest + faintest first
			var ring := PackedVector2Array()
			for p in pts:
				ring.append(p + drop + (p - c).normalized() * grow)
			draw_colored_polygon(ring, Color(shape_shadow_color, shape_shadow_color.a * 0.3))
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
		var d := pow(rng.randf(), grass_spread if art_grass else 0.7)   # 0 = horizon, 1 = bottom edge
		var y := lerpf(horizon_y + 6.0, size.y + 10.0, d)
		var x := rng.randf_range(-10.0, size.x + 10.0)
		var s := lerpf(0.35, 1.3, d)                 # perspective: near tufts are bigger
		var col := grass_far.lerp(grass_near, d).darkened(0.18 + rng.randf() * 0.1)
		if art_grass:   # your tuft, bottom-middle on the spot, hazier far away
			var ts := art_grass.get_size() * lerpf(grass_scale_far, grass_scale_near, d)
			var flip := 1.0 if rng.randf() < 0.5 else -1.0
			draw_set_transform(Vector2(x, y), 0.0, Vector2(flip, 1.0))
			draw_texture_rect(art_grass, Rect2(-ts.x * 0.5, -ts.y, ts.x, ts.y), false, Color(1, 1, 1, lerpf(0.55, 1.0, d)))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			continue
		for b in 3:
			var base := Vector2(x + (b - 1) * 4.0 * s, y)
			var tip := base + Vector2((b - 1) * 5.0 * s + rng.randf_range(-2, 2), -rng.randf_range(9.0, 15.0) * s)
			draw_line(base, tip, col, maxf(1.0, 2.2 * s), true)
	_draw_football()


## The football: one throw across the sky behind everything, nose following the
## arc, spinning a little on its long axis (a squash in its height) as it goes.
func _draw_football() -> void:
	var k := _football_k()
	if k < 0.0 or k > 1.0:
		return
	var p := football_from.lerp(football_to, k) + Vector2(0, -football_peak * 4.0 * k * (1.0 - k))
	var slope := (football_to - football_from) + Vector2(0, -football_peak * 4.0 * (1.0 - 2.0 * k))
	var sz := art_football.get_size() * (football_len / art_football.get_size().x)
	var spiral := 0.8 + 0.2 * absf(cos(k * football_beats * TAU))   # one spiral wobble per beat
	draw_set_transform(p, slope.angle(), Vector2(1.0, spiral))
	draw_texture_rect(art_football, Rect2(-sz * 0.5, sz), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
