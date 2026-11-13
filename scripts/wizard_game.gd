extends Node2D
## "Wizard Tower" (prototype). Call and response: the enemy tower on the horizon
## launches a bar of fireballs / iceballs straight up into the sky; one bar later
## they come back down out of the sky at you in the same order and rhythm. Blast
## each one on its beat with the OPPOSITE element.
##   A / Left / left click     ICE spell   (freezes fireballs)
##   D / Right / right click   FIRE spell  (melts iceballs)
##   Space start   R restart   Esc menu
##
## Art: art/wizard/*.png, exported from "wizard basics.kra" by tools/kra_export.ps1
## (at half size). Every frame keeps its place on the 3508x2480 Krita canvas
## (art/wizard/frames.json), so the wand, the spell and its burst line up exactly
## as drawn. The sky, hills, enemy tower and wall are placeholder drawings.

enum Phase { CARD, PLAY, DONE }

const VP := Vector2(1152, 648)
const PERFECT := 0.075
const GOOD := 0.15
const MISS_TAIL := 0.03
const TRAVEL_BEATS := 4.0          ## launch -> hit: exactly one bar later, same rhythm
## Flight: one arc from the enemy tower to the burst point, all on screen. The ball
## shoots up fast, hangs near the top of the sky (small and far away), then swoops
## at you, growing as it comes. Each beat of the bar gets its own lane across the
## sky, so a pattern hangs up there in order, like notes, before it comes down.
const APEX_Y := -40.0              ## height of the arc's control points (screen y)
const APEX_AT := 0.3               ## fraction of the flight spent climbing to the hang
const APEX_P := 0.45               ## how far along the path the hang point is
const LANE_SPREAD := 95.0          ## sideways spread per beat of the bar (screen px)
const MISS_FLY := 0.35             ## after a miss, seconds per "screen push" past the burst point
const FIRST_CALL_BAR := 2          ## two bars of music before the first pattern
## One entry per call bar: [beat in bar, element]. The answer is the next bar.
const PATTERNS := [
	[[0, "fire"], [2, "fire"]],
	[[0, "ice"], [2, "ice"]],
	[[0, "fire"], [2, "ice"]],
	[[0, "fire"], [1, "ice"], [2, "fire"], [3, "ice"]],
	[[0, "ice"], [1, "ice"], [2, "fire"]],
	[[0, "fire"], [1.5, "ice"], [3, "fire"]],
	[[0, "ice"], [1, "fire"], [2, "ice"], [3, "fire"]],
	[[0, "fire"], [1, "fire"], [2, "ice"], [3, "ice"]],
	[[0, "ice"], [1.5, "fire"], [2, "ice"]],
	[[0, "fire"], [1.5, "fire"], [3, "ice"]],
	[[0, "ice"], [1, "fire"], [1.5, "ice"], [3, "fire"]],
	[[0, "fire"], [1, "ice"], [2, "ice"], [2.5, "fire"]],
	[[0, "ice"], [0.5, "fire"], [2, "ice"], [2.5, "fire"]],
	[[0, "fire"], [1, "ice"], [2, "fire"], [3, "ice"], [3.5, "fire"]],
	[[0, "ice"], [1.5, "ice"], [2, "fire"], [3, "fire"]],
	[[0, "fire"], [0.5, "ice"], [1, "fire"], [2, "ice"], [3, "fire"]],
	[[0, "ice"], [1, "fire"], [2, "ice"], [2.5, "fire"], [3, "ice"]],
]

## --- art placement (Krita canvas -> screen) ---------------------------------
const ART := "res://art/wizard/"
const K := 1152.0 / 3508.0         ## screen px per Krita canvas px (canvas fills the width)
const CANVAS_OFF := Vector2(0, -166)  ## crop: wand at the bottom edge, sky on top
const TEX_SCALE := 2.0             ## canvas px per texture px (frames exported at half size)
const IMPACT := Vector2(1590, 1085)   ## canvas: centre of the spell's burst (firespell_6)
const BALL_HEAD := Vector2(115, 765)  ## canvas px inside the ball drawing: centre of its head
const BALL_DIR_DEG := 150.9        ## direction the drawn comet flies (tail -> head)
const BALL_FPS := 12.0
const BALL_SIZE := 0.62            ## overall size of the fire/ice balls (1.0 = as drawn)
const IMPACT_FRAME := 1.0 / 26.0   ## seconds per burst frame (spell frames 5-7)
const FIZZLE_TRAVEL := 0.08        ## a spell with nothing to hit: frames 0-4, then fades
const SPELL_TRAVEL := 0.07         ## the spell zips out this long before it hits (frames 0-4)
const FADE := 0.1
## Fallback canvas boxes if frames.json is missing (top-left of each layer).
const BOX := {"wand": Vector2(452, 1775), "fireball": Vector2(1695, 469),
	"iceball": Vector2(1695, 469), "firespell": Vector2(388, 551), "icespell": Vector2(388, 566),
	"gnome": Vector2(0, 1772), "gnome_hands": Vector2(609, 2115)}
const EYES_SHUT_CAST := 0.18       ## gnome squeezes its eyes shut (gnome_1) this long per cast
const EYES_SHUT_HURT := 0.35       ## ...and this long when a ball gets through

## --- scene layout (screen px) -------------------------------------------------
const HORIZON := 430.0
const ENEMY := Vector2(1010, 430)  ## base of the enemy tower, far away on the horizon
const ENEMY_TOP := Vector2(1010, 352)
const WALL_Y := 572.0
const COL := {"fire": Color(1.0, 0.42, 0.14), "ice": Color(0.45, 0.78, 1.0)}
const SKY := Color(0.106, 0.122, 0.231)
const INK := Color(0.2, 0.14, 0.12)

@onready var audio: AudioStreamPlayer = $AudioStreamPlayer

var _tex := {}                     ## layer name -> Array[Texture2D]
var _box := {}                     ## layer name -> canvas top-left
var _sfx := {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _font: Font
var _stars: Array[Vector3] = []

var _phase := Phase.CARD
var _balls: Array = []             ## { kind, launch_t, hit_t, arrive_v, state, ... }
var _spells: Array = []            ## { kind, t0, impact, fizzle }
var _pops: Array = []              ## { text, col, t0 } grade text by the burst
var _scars: Array = []             ## { kind, x } scorch / frost marks on your wall
var _cast_v := -10.0               ## visual time of the last cast (wand recoil)
var _hurt := {}                    ## { kind, v } last hit you took (flash + shake)
var _tally := {"Perfect": 0, "Good": 0, "Miss": 0}
var _results: Results          ## the counting-up percent on the results screen

var _impact_s: Vector2             ## burst point on screen
var _dir: Vector2                  ## comet travel direction on screen


var _pause: PauseMenu

func _ready() -> void:
	_pause = PauseMenu.attach(self, _start)   # Esc: Continue / Retry / Quit
	_results = Results.new()
	add_child(_results)
	_font = ThemeDB.fallback_font
	# the art is drawn big and shown small: mipmaps stop it shimmering as it scales
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_load_art()
	for k in ["fire", "ice", "hurt"]:
		_sfx[k] = _synth(k)
	for k in ["fire", "ice"]:
		_sfx["burst_" + k] = _synth_burst(k)
		_sfx["cast_" + k] = _synth_cast(k)
	for i in 16:                       # bursts ring ~1.5 s, so leave room for overlaps
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 90:
		_stars.append(Vector3(rng.randf() * VP.x, rng.randf() * (HORIZON - 30.0), rng.randf_range(0.8, 2.2)))

	_impact_s = _c2s(IMPACT)
	_dir = Vector2.from_angle(deg_to_rad(BALL_DIR_DEG))

	Conductor.stream_player = audio
	Conductor.bpm = 128.0
	Conductor.first_beat_offset = 0.0
	Conductor.video_offset = 0.0
	Conductor.input_offset = Settings.input_offset(0.131)
	Conductor.song_finished.connect(_on_song_finished)


func _exit_tree() -> void:
	Conductor.song_finished.disconnect(_on_song_finished)
	Conductor.stop()
	Conductor.stream_player = null


func _load_art() -> void:
	var boxes := {}
	var f := FileAccess.open(ART + "frames.json", FileAccess.READ)
	if f:
		var j = JSON.parse_string(f.get_as_text())
		if j is Dictionary and j.has("layers"):
			boxes = j["layers"]
	for layer in BOX:
		_box[layer] = BOX[layer]
		if boxes.has(layer):
			var b: Array = boxes[layer]["box"]
			_box[layer] = Vector2(b[0], b[1])
		var frames: Array[Texture2D] = []
		if ResourceLoader.exists(ART + layer + ".png"):
			frames.append(load(ART + layer + ".png"))
		var i := 0
		while ResourceLoader.exists(ART + "%s_%d.png" % [layer, i]):
			frames.append(load(ART + "%s_%d.png" % [layer, i]))
			i += 1
		_tex[layer] = frames


func _c2s(p: Vector2) -> Vector2:
	return p * K + CANVAS_OFF


# --- flow ------------------------------------------------------------------------

func _start() -> void:
	Conductor.stop()
	_balls.clear()
	_spells.clear()
	_pops.clear()
	_scars.clear()
	_hurt = {}
	_tally = {"Perfect": 0, "Good": 0, "Miss": 0}
	if _results:
		_results.reset()
	var bar := FIRST_CALL_BAR
	for pat in PATTERNS:
		for n in pat:
			var launch_beat: float = bar * 4 + float(n[0])
			var hit_t := Conductor.time_of_beat(launch_beat + TRAVEL_BEATS)
			_balls.append({"kind": n[1], "launch_t": Conductor.time_of_beat(launch_beat),
				"hit_t": hit_t, "arrive_v": hit_t + Conductor.input_offset,
				"lane": float(n[0]), "state": "fly", "launched": false, "impact": -1.0, "burst_sfx": null, "hurt": false})
		bar += 2
	_phase = Phase.PLAY
	Conductor.play()


func _on_song_finished() -> void:
	if _phase == Phase.PLAY:
		_phase = Phase.DONE


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ESCAPE:
				if _phase == Phase.DONE:    # results screen: straight to the menu
					get_tree().change_scene_to_file("res://MainMenu.tscn")
				else:
					_pause.open()
				get_viewport().set_input_as_handled()
			KEY_R:
				_start()
			KEY_SPACE, KEY_ENTER:
				if _phase != Phase.PLAY:
					_start()
			KEY_A, KEY_LEFT:
				_cast("ice")
			KEY_D, KEY_RIGHT:
				_cast("fire")
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_cast("ice")
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			_cast("fire")


## A spell fires every press. If a ball is inside the hit window, the spell
## flies to the burst point and lands exactly when the ball gets there.
func _cast(kind: String) -> void:
	if _phase != Phase.PLAY:
		return
	var now := Conductor.live_position()
	var v := now + Conductor.video_offset
	_cast_v = v
	var best := -1
	var best_err := INF
	for i in _balls.size():
		var b: Dictionary = _balls[i]
		if b["state"] != "fly":
			continue
		var err: float = now - Conductor.input_offset - b["hit_t"]
		if absf(err) <= GOOD and absf(err) < absf(best_err):
			best = i
			best_err = err
	var spell := {"kind": kind, "t0": v, "impact": -1.0}
	if best < 0:
		_play("cast_" + kind, -4.0)
	else:
		var b: Dictionary = _balls[best]
		if b["kind"] == kind:          # same element just feeds it -- it gets through
			b["state"] = "wrong"
			_cut_burst(b)
			_miss()
			_play("cast_" + kind, -4.0)
		else:
			var grade := "Perfect" if absf(best_err) <= PERFECT else "Good"
			b["state"] = "target"
			spell["impact"] = maxf(v + 0.05, b["arrive_v"])
			b["impact"] = spell["impact"]
			_tally[grade] += 1
			_pops.append({"text": grade + "!" if grade == "Perfect" else grade,
				"col": COL[kind], "t0": spell["impact"]})
	_spells.append(spell)


## A ball that got through: silence its on-beat burst if it's still ringing.
func _cut_burst(b: Dictionary) -> void:
	var p: AudioStreamPlayer = b["burst_sfx"]
	if p != null and p.playing and p.stream in [_sfx["burst_fire"], _sfx["burst_ice"]]:
		# quick fade rather than a hard stop, which would click
		var tw := create_tween()
		tw.tween_property(p, "volume_db", -60.0, 0.06)
		tw.tween_callback(p.stop)


func _miss() -> void:
	_tally["Miss"] += 1


# --- clock -----------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _phase == Phase.PLAY and Conductor.playing:
		var pos := Conductor.song_position
		var v := Conductor.visual_position
		var lat := AudioServer.get_output_latency()
		for b in _balls:
			# the launch sound is scheduled so it comes out of the speakers on the beat
			if not b["launched"] and pos >= b["launch_t"] - lat:
				b["launched"] = true
				_play(b["kind"], -2.0 if b["kind"] == "fire" else -8.0)
			# The burst is scheduled to sound exactly on the beat, like the launch.
			# Waiting for the press would make it late by the player's whole input
			# latency (a press only registers ~input_offset after the beat it hits).
			if b["burst_sfx"] == null and b["state"] in ["fly", "target"] and pos >= b["hit_t"] - lat:
				b["burst_sfx"] = _play("burst_" + ("ice" if b["kind"] == "fire" else "fire"), -2.0)
			if b["state"] == "fly" and pos - Conductor.input_offset > b["hit_t"] + GOOD + MISS_TAIL:
				b["state"] = "miss"
				_cut_burst(b)
				_miss()
			if b["state"] in ["miss", "wrong"] and not b["hurt"] and v - b["arrive_v"] >= 0.8 * MISS_FLY:
				b["hurt"] = true
				_hurt = {"kind": b["kind"], "v": v}
				_scars.append({"kind": b["kind"], "x": randf_range(330.0, 760.0)})
				_play("hurt", 0.0)
		_spells = _spells.filter(func(s): return _spell_alpha(s, v) > 0.0)
		_pops = _pops.filter(func(p): return v - p["t0"] < 0.7)
	# screen shake when a ball gets through
	var shake := 0.0
	if not _hurt.is_empty():
		shake = maxf(0.0, 1.0 - (Conductor.visual_position - _hurt["v"]) / 0.3) * 9.0
	position = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	queue_redraw()


# --- drawing ---------------------------------------------------------------------

func _draw() -> void:
	var v := Conductor.visual_position if _phase != Phase.CARD else 0.0
	var beat_pulse := 0.0
	if _phase == Phase.PLAY:
		beat_pulse = exp(-fposmod(Conductor.song_position_in_beats, 1.0) * 5.0)
	_draw_backdrop(beat_pulse)
	_draw_enemy(v)
	_draw_wall()
	_draw_wand(v)
	for s in _spells:
		_draw_spell(s, v)
	# far (small) balls first so the ones about to hit you are on top
	var order := _balls.filter(func(b): return v >= b["launch_t"] and v < b["arrive_v"] + 2.0 * MISS_FLY)
	order.sort_custom(func(a, b): return a["arrive_v"] > b["arrive_v"])
	for b in order:
		_draw_ball(b, v)
	if not _hurt.is_empty():
		var a := maxf(0.0, 1.0 - (v - _hurt["v"]) / 0.35) * 0.35
		if a > 0.0:
			var c: Color = COL[_hurt["kind"]]
			draw_rect(Rect2(-20, -20, VP.x + 40, VP.y + 40), Color(c, a))
	for p in _pops:
		var k := clampf((v - p["t0"]) / 0.7, 0.0, 1.0)
		if v >= p["t0"]:
			_text(p["text"], _impact_s + Vector2(-260, 90 - 30 * k), 32, Color(p["col"], 1.0 - k), true, 1.0 - k)
	_draw_hud()
	if _phase == Phase.CARD:
		_draw_card()
	elif _phase == Phase.DONE:
		_draw_results()


func _draw_backdrop(pulse: float) -> void:
	draw_rect(Rect2(-20, -20, VP.x + 40, VP.y + 40), SKY)
	for s in _stars:
		draw_circle(Vector2(s.x, s.y), s.z, Color(1, 1, 1, 0.45 + 0.4 * pulse * (s.z / 2.2)))
	draw_circle(Vector2(820, 90), 34, Color(0.96, 0.93, 0.8))
	draw_circle(Vector2(806, 82), 30, SKY)            # crescent
	# far hills: hazy, low contrast -- they push the enemy tower into the distance
	_ellipse(Vector2(900, HORIZON + 10), Vector2(420, 70), Color(0.23, 0.25, 0.39))
	_ellipse(Vector2(380, HORIZON + 18), Vector2(380, 52), Color(0.2, 0.22, 0.35))
	draw_rect(Rect2(-20, HORIZON, VP.x + 40, VP.y - HORIZON + 20), Color(0.165, 0.2, 0.25))
	for x in [-400.0, 200.0, 700.0, 1500.0]:          # ground lines converge on the enemy
		draw_line(ENEMY, Vector2(x, VP.y), Color(0.23, 0.27, 0.34), 1.0)


func _draw_enemy(v: float) -> void:
	var flash := 0.0
	var fc := Color.WHITE
	for b in _balls:
		var d: float = v - b["launch_t"]
		if d >= 0.0 and d < 0.25:
			flash = 1.0 - d / 0.25
			fc = COL[b["kind"]]
	var haze := Color(0.42, 0.36, 0.48)
	var squash := 1.0 - 0.08 * flash
	var top := ENEMY.y - (ENEMY.y - ENEMY_TOP.y) * squash
	draw_rect(Rect2(ENEMY.x - 13, top + 18, 26, ENEMY.y - top - 18), haze)
	draw_colored_polygon(PackedVector2Array([Vector2(ENEMY.x - 18, top + 18),
		Vector2(ENEMY.x, top - 8), Vector2(ENEMY.x + 18, top + 18)]), Color(0.55, 0.3, 0.42))
	draw_circle(Vector2(ENEMY.x, top + 34), 4, Color(1, 0.6, 0.3, 0.8))
	if flash > 0.0:
		draw_circle(Vector2(ENEMY.x, top - 8), 6 + 16 * flash, Color(fc, 0.7 * flash))


## Control points of a ball's arc (cubic Bezier), shifted sideways by its lane.
func _arc(b: Dictionary) -> Array:
	var dx: float = (b["lane"] - 1.5) * LANE_SPREAD
	return [ENEMY_TOP + Vector2(0, -8), Vector2(ENEMY_TOP.x + 60.0 + dx * 0.6, APEX_Y),
		Vector2(_impact_s.x + 240.0 + dx, APEX_Y), _impact_s]


func _bez(c: Array, p: float) -> Vector2:
	var q := 1.0 - p
	return c[0] * q * q * q + c[1] * 3.0 * q * q * p + c[2] * 3.0 * q * p * p + c[3] * p * p * p


## Flight progress -> path position: a fast climb, a slow menacing drift at the
## top, then an accelerating swoop that lands exactly on arrive_v.
func _path_p(u: float) -> float:
	if u < APEX_AT:
		var k := u / APEX_AT
		return APEX_P * (1.0 - (1.0 - k) * (1.0 - k))
	var w := (u - APEX_AT) / (1.0 - APEX_AT)
	return APEX_P + (1.0 - APEX_P) * (0.2 * w + 0.8 * w * w * w)


func _draw_ball(b: Dictionary, v: float) -> void:
	if b["state"] == "target" and v >= b["impact"]:
		return                         # blasted: the spell's burst takes over
	var c := _arc(b)
	var u: float = (v - b["launch_t"]) / (b["arrive_v"] - b["launch_t"])
	if b["state"] == "target":
		u = minf(u, 1.0)               # a late cast: it waits for the spell
	var pos: Vector2
	var s: float
	var tangent: Vector2
	if u <= 1.0:
		var p := _path_p(u)
		pos = _bez(c, p)
		tangent = _bez(c, minf(p + 0.01, 1.0)) - _bez(c, maxf(p - 0.01, 0.0))
		s = lerpf(0.07, 1.0, pow(p, 2.6))   # depth: tiny far away, full size at the burst point
	else:
		# missed: it keeps coming, over your wall and past you
		tangent = c[3] - c[2]
		var extra: float = (v - b["arrive_v"]) / MISS_FLY
		pos = _impact_s + tangent.normalized() * extra * 520.0
		s = 1.0 + extra * 0.9
	var rot := tangent.angle() - deg_to_rad(BALL_DIR_DEG)
	_draw_comet(b, pos, s, rot, v, clampf(u * 12.0, 0.0, 1.0))


func _draw_comet(b: Dictionary, head: Vector2, s: float, rot: float, v: float, a: float) -> void:
	var frames: Array = _tex[b["kind"] + "ball"]
	if frames.is_empty():
		draw_circle(head, 40.0 * s * BALL_SIZE, Color(COL[b["kind"]], a))
		return
	var tex: Texture2D = frames[int(v * BALL_FPS) % frames.size()]
	draw_set_transform(head, rot, Vector2.ONE * s * BALL_SIZE * K * TEX_SCALE)
	draw_texture(tex, -BALL_HEAD / TEX_SCALE, Color(1, 1, 1, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _spell_frame(s: Dictionary, v: float) -> int:
	var t0: float = s["t0"]
	var imp: float = s["impact"]
	if imp < 0.0:
		return clampi(int(5.0 * (v - t0) / FIZZLE_TRAVEL), 0, 4)
	if v < imp:
		var start := _spell_start(s)
		return clampi(int(5.0 * (v - start) / maxf(imp - start, 0.001)), 0, 4)
	return mini(5 + int((v - imp) / IMPACT_FRAME), 7)


## An early cast waits at the wand and zips out SPELL_TRAVEL before the hit, so the
## spell always looks fast instead of drifting slowly toward a far-off ball.
func _spell_start(s: Dictionary) -> float:
	if s["impact"] < 0.0:
		return s["t0"]
	return maxf(s["t0"], s["impact"] - SPELL_TRAVEL)


func _spell_alpha(s: Dictionary, v: float) -> float:
	var t0: float = s["t0"]
	var imp: float = s["impact"]
	var done := (t0 + FIZZLE_TRAVEL) if imp < 0.0 else (imp + 3.0 * IMPACT_FRAME)
	return clampf(1.0 - (v - done) / FADE, 0.0, 1.0)


func _draw_spell(s: Dictionary, v: float) -> void:
	var layer: String = s["kind"] + "spell"
	var frames: Array = _tex[layer]
	if v < _spell_start(s) or frames.is_empty():
		return
	var tex: Texture2D = frames[mini(_spell_frame(s, v), frames.size() - 1)]
	draw_texture_rect(tex, Rect2(_c2s(_box[layer]), tex.get_size() * TEX_SCALE * K), false,
		Color(1, 1, 1, _spell_alpha(s, v)))


func _draw_wand(v: float) -> void:
	var frames: Array = _tex["wand"]
	if frames.is_empty():
		return
	var kick := Vector2(-12, 12) * maxf(0.0, 1.0 - (v - _cast_v) / 0.16)
	# the gnome stands behind the wand and its hands go over it, as layered in Krita;
	# it rocks back a little less than the wand when you cast
	var gnome: Array = _tex["gnome"]
	if not gnome.is_empty():
		# eyes shut only while casting or when a ball gets through
		var shut := v - _cast_v >= 0.0 and v - _cast_v < EYES_SHUT_CAST
		if not _hurt.is_empty() and v - _hurt["v"] < EYES_SHUT_HURT:
			shut = true
		var g: Texture2D = gnome[1 if shut and gnome.size() > 1 else 0]
		_draw_layer(g, "gnome", kick * 0.5)
	_draw_layer(frames[0], "wand", kick)
	if not _tex["gnome_hands"].is_empty():
		_draw_layer(_tex["gnome_hands"][0], "gnome_hands", kick)


func _draw_layer(tex: Texture2D, layer: String, shift: Vector2) -> void:
	draw_texture_rect(tex, Rect2(_c2s(_box[layer]) + shift, tex.get_size() * TEX_SCALE * K), false)


## Top of your tower: the battlements you stand behind. Placeholder until drawn.
func _draw_wall() -> void:
	var stone := Color(0.42, 0.44, 0.52)
	var dark := Color(0.32, 0.33, 0.41)
	draw_rect(Rect2(-20, WALL_Y, VP.x + 40, VP.y - WALL_Y + 20), stone)
	draw_rect(Rect2(-20, WALL_Y, VP.x + 40, 8), dark)
	var x := -30.0
	while x < VP.x:
		draw_rect(Rect2(x, WALL_Y - 46, 84, 48), stone)
		draw_rect(Rect2(x, WALL_Y - 46, 14, 48), dark)
		x += 150.0
	for sc in _scars:
		var c: Color = Color(0.12, 0.08, 0.07, 0.75) if sc["kind"] == "fire" else Color(0.85, 0.95, 1.0, 0.75)
		_ellipse(Vector2(sc["x"], WALL_Y + 30), Vector2(26, 11), c)


func _draw_hud() -> void:
	_text("A / Left", Vector2(VP.x - 300, VP.y - 22), 18, Color(1, 1, 1, 0.8))
	_text("ICE", Vector2(VP.x - 222, VP.y - 22), 18, COL["ice"])
	_text("D / Right", Vector2(VP.x - 160, VP.y - 22), 18, Color(1, 1, 1, 0.8))
	_text("FIRE", Vector2(VP.x - 74, VP.y - 22), 18, COL["fire"])


func _draw_card() -> void:
	_panel(Rect2(226, 120, 700, 360))
	_text("WIZARD TOWER", Vector2(576, 180), 40, INK, true)
	_text("The enemy tower fires a pattern into the sky.", Vector2(576, 236), 22, INK, true)
	_text("One bar later it rains back down on you, same rhythm.", Vector2(576, 268), 22, INK, true)
	_text("Blast each ball as it reaches the burst point,", Vector2(576, 316), 22, INK, true)
	_text("with the OPPOSITE element:", Vector2(576, 348), 22, INK, true)
	_text("A / Left  =  ICE  (freezes fire)", Vector2(576, 392), 22, COL["ice"].darkened(0.35), true)
	_text("D / Right  =  FIRE  (melts ice)", Vector2(576, 424), 22, COL["fire"].darkened(0.25), true)
	_text("SPACE to start", Vector2(576, 464), 18, INK.lightened(0.4), true)


func _draw_results() -> void:
	_panel(Rect2(326, 150, 500, 320))
	_text("TOWER DEFENDED!" if _tally["Miss"] <= 6 else "THE TOWER IS SCORCHED", Vector2(576, 210), 32, INK, true)
	var got: int = _tally["Perfect"] + _tally["Good"]
	_results.draw_percent(self, _font, Vector2(576, 320), got, got + _tally["Miss"])
	_text("SPACE / R to play again   -   Esc for menu", Vector2(576, 440), 18, INK.lightened(0.4), true)


# --- helpers ---------------------------------------------------------------------

func _text(t: String, pos: Vector2, size: int, col: Color, centred := false, outline := 0.0) -> void:
	if centred:
		var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		pos.x -= w / 2.0
	if outline > 0.0:
		draw_string_outline(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color(SKY, outline))
	draw_string(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _panel(r: Rect2) -> void:
	draw_rect(r.grow(4), INK)
	draw_rect(r, Color(1, 0.97, 0.88))


func _ellipse(c: Vector2, radius: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		pts.append(c + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_colored_polygon(pts, col)


func _play(key: String, db: float) -> AudioStreamPlayer:
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = _sfx[key]
	p.volume_db = db
	p.play()
	return p


## Placeholder sounds, synthesised so the prototype needs no files: fire launch =
## low whoomp, ice launch = high ting (so the call can be played by ear), burst,
## hurt thud, and a soft whoosh for an empty cast.
func _synth(kind: String) -> AudioStreamWAV:
	const RATE := 44100
	var dur: float = {"fire": 0.26, "ice": 0.34, "hurt": 0.4, "cast": 0.12}[kind]
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var s := 0.0
		if kind == "fire":
			phase += TAU * lerpf(230.0, 55.0, u) / RATE
			lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.12)
			s = (sin(phase) * 0.8 + lp * 0.9) * exp(-5.0 * u) * minf(1.0, t * 300.0)
		elif kind == "ice":
			s = (sin(TAU * 1568.0 * t) + 0.5 * sin(TAU * 2349.0 * t) + 0.3 * sin(TAU * 3136.0 * t)) \
				* 0.4 * exp(-7.0 * u) * minf(1.0, t * 800.0)
		elif kind == "hurt":
			phase += TAU * lerpf(130.0, 38.0, u) / RATE
			s = sin(phase) * exp(-4.0 * u) * 0.95
		else:
			lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.5)
			s = lp * 0.45 * sin(PI * u)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


## The spell explosions, one per spell element (the ball's opposite):
##   burst_fire  fire spell melts an iceball: sub boom, crack, rolling fiery roar
##               with crackles, and a steam hiss as the ice goes
##   burst_ice   ice spell freezes a fireball: sub boom, crack, a shower of
##               shattering crystal pings and a shimmering frozen chord
## Both get a short synthetic reverb tail so they sound big.
func _synth_burst(spell: String) -> AudioStreamWAV:
	const RATE := 44100
	var n := int(1.0 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 if spell == "fire" else 23
	var ice := spell == "ice"
	var sub_phase := 0.0
	var roar := 0.0
	var roar2 := 0.0
	var hiss_lp := 0.0
	var crack_lp := 0.0
	# shatter pings for the ice burst: [start sample, freq, amp]
	var pings: Array = []
	if ice:
		for k in 46:
			var at := pow(rng.randf(), 2.2) * 0.42
			pings.append([int(at * RATE), rng.randf_range(2200.0, 7400.0), rng.randf_range(0.05, 0.13) * (1.0 - at * 1.6)])
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		# sub boom: a fast pitch drop you feel more than hear
		var f0 := (45.0 if ice else 38.0) + (100.0 if ice else 80.0) * exp(-t * 22.0)
		sub_phase += TAU * f0 / RATE
		s += sin(sub_phase) * exp(-t * 4.5) * minf(1.0, t * 400.0) * 0.95
		# crack: very short bright noise transient
		var nz := rng.randf_range(-1.0, 1.0)
		crack_lp += 0.3 * (nz - crack_lp)
		s += (nz - crack_lp) * exp(-t * 70.0) * 0.9
		if ice:
			# shimmering frozen chord (E6 B6 E7), each note doubled slightly sharp so it beats
			var shim := 0.0
			for f in [1318.5, 1975.5, 2637.0]:
				shim += sin(TAU * f * t) + sin(TAU * f * 1.006 * t)
			s += shim * 0.05 * exp(-t * 3.2) * minf(1.0, t * 60.0)
			# frosty breath: airy high noise
			s += (nz - crack_lp) * 0.16 * exp(-t * 5.0) * minf(1.0, t * 30.0)
		else:
			# rolling roar: noise through a closing low-pass, twice for body
			var cut := 0.02 + 0.3 * exp(-t * 6.0)
			roar += cut * (nz - roar)
			roar2 += cut * (roar - roar2)
			s += roar2 * 3.2 * exp(-t * 3.6) * minf(1.0, t * 120.0)
			# crackles, thinning out
			if rng.randf() < 0.004 * exp(-t * 4.0):
				s += rng.randf_range(-0.9, 0.9)
			# steam hiss from the melting ice
			hiss_lp += 0.5 * (nz - hiss_lp)
			s += (nz - hiss_lp) * 0.22 * smoothstep(0.03, 0.15, t) * exp(-t * 4.0)
		buf[i] = s
	for p in pings:
		var start: int = p[0]
		var ph := 0.0
		for j in range(start, mini(start + int(0.18 * RATE), n)):
			var tt := float(j - start) / RATE
			ph += TAU * p[1] / RATE
			buf[j] += sin(ph) * p[2] * exp(-tt * 30.0)
	return _to_wav(_reverb(buf, RATE), RATE)


## Fizzle cast: a quick swoosh flavoured by the element.
func _synth_cast(spell: String) -> AudioStreamWAV:
	const RATE := 44100
	var n := int(0.32 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / 0.32
		var nz := rng.randf_range(-1.0, 1.0)
		var cut := 0.04 + 0.4 * u
		lp += cut * (nz - lp)
		lp2 += cut * (lp - lp2)
		var s := (lp - lp2) * 1.6 * sin(PI * pow(u, 0.6))
		if spell == "ice":
			s += sin(TAU * 2637.0 * t) * 0.12 * exp(-t * 14.0)
		else:
			s += lp2 * 0.8 * exp(-t * 8.0)
		buf[i] = s
	return _to_wav(_reverb(buf, RATE, 0.2), RATE)


## Small Schroeder reverb: four damped combs into two all-passes. Adds ~0.6 s of tail.
func _reverb(dry: PackedFloat32Array, rate: int, wet := 0.32) -> PackedFloat32Array:
	var n := dry.size() + int(0.6 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var combs := [0.0297, 0.0371, 0.0411, 0.0437]
	for c in combs:
		var d := int(c * rate)
		var line := PackedFloat32Array()
		line.resize(d)
		var idx := 0
		var damp := 0.0
		for i in n:
			var x := dry[i] if i < dry.size() else 0.0
			var y := line[idx]
			damp += 0.35 * (y - damp)
			line[idx] = x + damp * 0.8
			idx = (idx + 1) % d
			out[i] += y * 0.25
	for ap in [[0.005, 0.7], [0.0017, 0.7]]:
		var d := int(ap[0] * rate)
		var g: float = ap[1]
		var line := PackedFloat32Array()
		line.resize(d)
		var idx := 0
		for i in n:
			var buf_out := line[idx]
			var x := out[i]
			var y := -g * x + buf_out
			line[idx] = x + g * y
			idx = (idx + 1) % d
			out[i] = y
	for i in n:
		out[i] = (dry[i] if i < dry.size() else 0.0) + out[i] * wet
	return out


## Normalise to just under full scale and pack as 16-bit mono.
func _to_wav(buf: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var peak := 0.0001
	for x in buf:
		peak = maxf(peak, absf(x))
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] / peak * 0.95, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
