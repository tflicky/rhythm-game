extends Node2D
## "Boomerang" (prototype). Call and response: first the rhythm is played to you as
## sound only (the call), then you do it back. Throw with SPACE on the THROW beat; it
## flies out, counts its way through the air, and comes back -- press SPACE again
## to catch it on the CATCH beat. Three kinds, each with its own count:
##   red    "1 2 3 catch"          catch 4 beats after the throw
##   green  "1 & 2 & 3 & catch"    catch 4 beats after the throw, hops on every &
##   blue   "1 2 3 4 catch"        catch 5 beats after the throw (wait for the 4!)
##   Space / left click   throw + catch     Enter start   R restart   Esc menu
##
## All the counts are data in TYPES (beat offsets from the throw), and the level
## is the SEQUENCE list, so changing a timing or adding a kind is a one-line edit.
## Sounds are synthesised placeholders; drop real ones (e.g. a recorded voice
## counting) into res://audio/sfx/boomerang/ named count_1, count_2, count_3,
## count_4, count_and, throw, catch, bonk, and the thrower's cue noises cue_three,
## cue_and, cue_four, and the balloon pop (.wav or .ogg) and they're used.

enum Phase { CARD, PLAY, DONE }

const VP := Vector2(1152, 648)
const PERFECT := 0.07
const GOOD := 0.14
const MISS_TAIL := 0.03
## The CALL: the thrower makes their cue noise on each of these beats (relative to
## the throw), then you throw on the next one -- "cue, cue, THROW", all on the beat.
## Each kind of boomerang has its own noise, so you know what's coming by ear.
## Turn this off if your song has the cue noises baked into it.
const CUE_BEATS := [-2.0, -1.0]
const PLAY_CUE_SFX := true

## counts: [beat offset from the throw, text]. catch: beat offset of the catch.
## reach / lift / swirl shape the loop it flies; hop = bounce on every half beat.
const TYPES := {
	"three": {"counts": [[1.0, "1"], [2.0, "2"], [3.0, "3"]], "catch": 4.0,
		"col": Color(0.9, 0.28, 0.22), "reach": 500.0, "lift": 170.0, "swirl": 40.0, "hop": 0.0},
	"and": {"counts": [[1.0, "1"], [1.5, "&"], [2.0, "2"], [2.5, "&"], [3.0, "3"], [3.5, "&"]], "catch": 4.0,
		"col": Color(0.16, 0.66, 0.46), "reach": 540.0, "lift": 140.0, "swirl": 30.0, "hop": 34.0},
	"four": {"counts": [[1.0, "1"], [2.0, "2"], [3.0, "3"], [4.0, "4"]], "catch": 5.0,
		"col": Color(0.22, 0.42, 0.9), "reach": 680.0, "lift": 210.0, "swirl": 50.0, "hop": 0.0},
}

## The level, in order. One throw every SPACING beats, always on the downbeat of a
## bar (8 = every 2 bars). "rest" = skip one slot.
## Placeholder for the placeholder song (~152 beats at 128 BPM) -- redo it for yours.
const FIRST_THROW := 8.0
const SPACING := 8.0
const SEQUENCE := [
	"three", "three", "four", "three", "four", "four", "and", "three", "and",
	"four", "and", "and", "three", "four", "and", "three", "four", "and",
]
## Balloons drifting across the sky that the boomerang pops on these counts
## (beat offsets from the throw) -- only if you threw it on time.
const BALLOON_BEATS := {"three": [2.0], "and": [1.5, 2.5], "four": [2.0, 3.0]}
const BALLOON_COLS := [Color(0.95, 0.3, 0.45), Color(1.0, 0.8, 0.25), Color(0.55, 0.4, 0.9),
	Color(0.3, 0.75, 0.95), Color(1.0, 0.55, 0.2)]

## --- scene layout (screen px) -------------------------------------------------
const HORIZON := 440.0
const GROUND_NEAR := 612.0         ## shadow height when the boomerang is right by you
const FEET := Vector2(200, 600)
const BODY := Vector2(200, 522)
const HEAD := Vector2(200, 446)
const SHOULDER := Vector2(226, 494)
const HAND := Vector2(276, 502)    ## where it leaves from and comes back to
const SKY_TOP := Color(0.28, 0.2, 0.42)
const SKY_LOW := Color(0.98, 0.6, 0.36)
const SAND := Color(0.86, 0.6, 0.36)
const INK := Color(0.2, 0.14, 0.12)

@onready var audio: AudioStreamPlayer = $AudioStreamPlayer

var _sfx := {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _font: Font

var _phase := Phase.CARD
var _booms: Array = []
var _pops: Array = []              ## { text, col, v0, pos }
var _balloons: Array = []          ## { boom, hit_t, hit_v, pos, scale, col, vel, sway, state }
var _swing := {"kind": "", "v": -10.0}   ## last arm move: throw / catch / whiff / fumble
var _bonk_v := -10.0               ## when a missed boomerang last hit you on the head
var _tally := {"Perfect": 0, "Good": 0, "Miss": 0}


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_sfx["count_1"] = _load_sfx("count_1", _synth_tick(784.0, 0.16, 0.9))
	_sfx["count_2"] = _load_sfx("count_2", _synth_tick(880.0, 0.16, 0.9))
	_sfx["count_3"] = _load_sfx("count_3", _synth_tick(988.0, 0.16, 0.9))
	_sfx["count_4"] = _load_sfx("count_4", _synth_tick(1175.0, 0.16, 0.9))
	_sfx["count_and"] = _load_sfx("count_and", _synth_tick(1568.0, 0.08, 0.45))
	# placeholder cue "voices": red = "hah" (mid), green = "hee" (high), blue = "hoo" (low)
	_sfx["cue_three"] = _load_sfx("cue_three", _synth_vowel(200.0, 750.0, 1150.0))
	_sfx["cue_and"] = _load_sfx("cue_and", _synth_vowel(300.0, 320.0, 2300.0))
	_sfx["cue_four"] = _load_sfx("cue_four", _synth_vowel(130.0, 320.0, 800.0))
	_sfx["throw"] = _load_sfx("throw", _synth_whoosh(0.3, 0.06))
	_sfx["whiff"] = _synth_whoosh(0.16, 0.2)
	_sfx["pop"] = _load_sfx("pop", _synth_pop())
	_sfx["bonk"] = _load_sfx("bonk", _synth_bonk())
	var catch_fallback: AudioStream = _synth_thump()
	if ResourceLoader.exists("res://audio/sfx/catch.wav"):   # the monkey level's trimmed thunk
		catch_fallback = load("res://audio/sfx/catch.wav")
	_sfx["catch"] = _load_sfx("catch", catch_fallback)
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

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


func _load_sfx(key: String, fallback: AudioStream) -> AudioStream:
	for ext in ["wav", "ogg"]:
		var path := "res://audio/sfx/boomerang/%s.%s" % [key, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return fallback


# --- flow ------------------------------------------------------------------------

func _start() -> void:
	Conductor.stop()
	_booms.clear()
	_pops.clear()
	_swing = {"kind": "", "v": -10.0}
	_bonk_v = -10.0
	_tally = {"Perfect": 0, "Good": 0, "Miss": 0}
	_balloons.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var seen := {}
	var tb := FIRST_THROW
	for kind in SEQUENCE:
		if kind == "rest":
			tb += SPACING
			continue
		var ty: Dictionary = TYPES[kind]
		var throw_t := Conductor.time_of_beat(tb)
		var catch_t := Conductor.time_of_beat(tb + float(ty["catch"]))
		var cues: Array = []           # absolute times of the thrower's cue noises
		for off in CUE_BEATS:
			cues.append(Conductor.time_of_beat(tb + float(off)))
		var b := {"kind": kind, "beat": tb, "call_t": cues[0], "cues": cues,
			"throw_t": throw_t, "catch_t": catch_t,
			# the flight is drawn so it leaves / lands exactly when a perfect press registers
			"depart_v": throw_t + Conductor.input_offset, "arrive_v": catch_t + Conductor.input_offset,
			"state": "wait", "call_i": 0, "throw_sfx": false, "catch_sfx": false, "thrown_ok": false,
			# the count board is a crutch: it only shows the first time you meet each colour
			"board": not seen.has(kind),
			"count_i": 0, "miss_v": 0.0, "bonked": false}
		seen[kind] = true
		_booms.append(b)
		for off in BALLOON_BEATS[kind]:
			var hit_v: float = b["depart_v"] + float(off) * Conductor.seconds_per_beat
			var f := _flight(b, hit_v)
			_balloons.append({"boom": b, "hit_t": throw_t + float(off) * Conductor.seconds_per_beat,
				"hit_v": hit_v, "pos": f["pos"], "scale": f["scale"], "state": "float",
				"col": BALLOON_COLS[rng.randi() % BALLOON_COLS.size()],
				"vel": Vector2(rng.randf_range(-85.0, -55.0), rng.randf_range(-22.0, -10.0)),
				"sway": rng.randf() * TAU})
		tb += SPACING
	_phase = Phase.PLAY
	Conductor.play()


func _on_song_finished() -> void:
	if _phase == Phase.PLAY:
		_phase = Phase.DONE


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://MainMenu.tscn")
			KEY_R:
				_start()
			KEY_ENTER:
				if _phase != Phase.PLAY:
					_start()
			KEY_SPACE:
				if _phase != Phase.PLAY:
					_start()
				else:
					_press()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if _phase == Phase.PLAY:
			_press()


## One button does both: it goes to whichever throw or catch is closest in time.
func _press() -> void:
	var now := Conductor.live_position()
	var v := now + Conductor.video_offset
	var adj := now - Conductor.input_offset
	var best := -1
	var best_err := INF
	for i in _booms.size():
		var b: Dictionary = _booms[i]
		var target := -1.0
		if b["state"] == "wait":
			target = b["throw_t"]
		elif b["state"] == "out":
			target = b["catch_t"]
		if target < 0.0:
			continue
		var err := adj - target
		if absf(err) <= GOOD and absf(err) < absf(best_err):
			best = i
			best_err = err
	if best < 0:
		_swing = {"kind": "whiff", "v": v}
		_play("whiff", -10.0)
		return
	var b: Dictionary = _booms[best]
	var grade := "Perfect" if absf(best_err) <= PERFECT else "Good"
	var col: Color = TYPES[b["kind"]]["col"]
	if b["state"] == "wait":
		b["state"] = "out"
		b["thrown_ok"] = true              # a clean throw pops the balloons on its path
		_swing = {"kind": "throw", "v": maxf(v, b["depart_v"] - 0.05)}
		_pops.append({"text": "Nice throw!" if grade == "Perfect" else "Throw", "col": col,
			"v0": b["depart_v"], "pos": HAND + Vector2(70, -40)})
	else:
		b["state"] = "caught"
		_swing = {"kind": "catch", "v": maxf(v, b["arrive_v"])}
		_pops.append({"text": grade + "!" if grade == "Perfect" else grade, "col": col,
			"v0": b["arrive_v"], "pos": HAND + Vector2(70, -40)})
	_hit(grade)


func _hit(grade: String) -> void:
	_tally[grade] += 1


func _miss(text: String, at_v: float) -> void:
	_tally["Miss"] += 1
	_pops.append({"text": text, "col": Color(0.85, 0.15, 0.15), "v0": at_v, "pos": HAND + Vector2(70, -40)})


# --- clock -----------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _phase == Phase.PLAY and Conductor.playing:
		var pos := Conductor.song_position
		var v := Conductor.visual_position
		var adj := pos - Conductor.input_offset
		var lat := AudioServer.get_output_latency()
		var spb := Conductor.seconds_per_beat
		for b in _booms:
			var ty: Dictionary = TYPES[b["kind"]]
			# every sound is scheduled so it comes out of the speakers on its beat
			var cues: Array = b["cues"]
			if b["call_i"] < cues.size() and pos >= float(cues[b["call_i"]]) - lat:
				b["call_i"] += 1
				if PLAY_CUE_SFX:
					_play("cue_" + b["kind"], 0.0)
			if not b["throw_sfx"] and pos >= b["throw_t"] - lat:
				b["throw_sfx"] = true
				_play("throw", -4.0)
			var counts: Array = ty["counts"]
			if b["count_i"] < counts.size():
				var cnt: Array = counts[b["count_i"]]
				if pos >= b["throw_t"] + float(cnt[0]) * spb - lat:
					b["count_i"] += 1
					var label: String = cnt[1]
					_play("count_and" if label == "&" else "count_" + label, -3.0)
			# the catch thunk plays on the beat, like the monkey level -- your hands
			# show whether you actually caught it
			if not b["catch_sfx"] and b["state"] in ["out", "caught"] and pos >= b["catch_t"] - lat:
				b["catch_sfx"] = true
				_play("catch", 0.0)
			# windows running out
			if b["state"] == "wait" and adj > b["throw_t"] + GOOD + MISS_TAIL:
				b["state"] = "out"         # you fumble it out anyway, so the catch still counts
				_swing = {"kind": "fumble", "v": v}
				_miss("Fumble!", v)
			elif b["state"] == "out" and adj > b["catch_t"] + GOOD + MISS_TAIL:
				b["state"] = "bonk"
				b["miss_v"] = v
				_miss("Ouch!", v)
			if b["state"] == "bonk" and not b["bonked"] and v - b["miss_v"] >= BONK_REACH:
				b["bonked"] = true
				_bonk_v = v
				_play("bonk", 0.0)
		# balloons pop with a bang on their count -- the sound on the beat, like everything else
		for bl in _balloons:
			if bl["state"] == "float" and bl["boom"]["thrown_ok"] and pos >= bl["hit_t"] - lat:
				bl["state"] = "pop"
				_play("pop", -2.0)
		_pops = _pops.filter(func(p): return v - p["v0"] < 0.7)
	queue_redraw()


# --- flight ----------------------------------------------------------------------

const BONK_REACH := 0.14           ## seconds from a missed catch to the boomerang hitting your head

## u = 0 at your hand, 1 back at your hand. It goes out high, comes back low, and
## shrinks with distance (depth = how far away it is, 0..1).
func _flight(b: Dictionary, v: float) -> Dictionary:
	var ty: Dictionary = TYPES[b["kind"]]
	var u: float = (v - b["depart_v"]) / (b["arrive_v"] - b["depart_v"])
	u = clampf(u, 0.0, 1.0)
	var out := sin(PI * u)
	var pos := HAND + Vector2(ty["reach"] * out, -ty["lift"] * out - ty["swirl"] * sin(TAU * u))
	var depth := out
	var hop: float = ty["hop"]
	if hop > 0.0:
		# a bounce off every count, beat and "&" alike
		var fb: float = (v - b["depart_v"]) / Conductor.seconds_per_beat
		pos.y -= hop * absf(sin(TAU * fb)) * (1.0 - 0.5 * depth)
	return {"pos": pos, "depth": depth, "scale": lerpf(1.0, 0.45, depth)}


func _draw_flying(b: Dictionary, v: float) -> void:
	var col: Color = TYPES[b["kind"]]["col"]
	var spin: float = (v - b["depart_v"]) * 19.0
	if b["state"] == "bonk":
		var k: float = v - b["miss_v"]
		var head_hit := HEAD + Vector2(14, -26)
		var p: Vector2
		if k < BONK_REACH:
			p = HAND.lerp(head_hit, k / BONK_REACH)
		else:
			var t := k - BONK_REACH       # pings up off your head, then drops off screen
			p = head_hit + Vector2(-140.0 * t, -260.0 * t + 1500.0 * t * t)
			if p.y > VP.y + 60.0:
				return
		_draw_shadow(Vector2(p.x, GROUND_NEAR), 1.0)
		_draw_boomerang(p, spin, 1.0, col)
		return
	var f := _flight(b, v)
	var pos: Vector2 = f["pos"]
	var depth: float = f["depth"]
	var s: float = f["scale"]
	_draw_shadow(Vector2(pos.x, lerpf(GROUND_NEAR, HORIZON + 22.0, depth)), s)
	# a faint trail so you can read the loop it's flying
	for i in range(1, 6):
		var bv: float = v - i * 0.025
		if bv < b["depart_v"]:
			break
		var g := _flight(b, bv)
		_draw_boomerang(g["pos"], spin - i * 0.5, g["scale"], Color(col, 0.18 - i * 0.03))
	_draw_boomerang(pos, spin, s, col)


## Balloons only appear once you've thrown cleanly -- every balloon you see gets
## popped. They drift in from the right, timed so they're exactly on the
## boomerang's path when it gets there. Placeholder drawing.
func _draw_balloon(bl: Dictionary, v: float) -> void:
	if not bl["boom"]["thrown_ok"]:
		return
	var dt: float = v - bl["hit_v"]
	var appear: float = bl["boom"]["depart_v"] - bl["hit_v"]   # (negative) seconds before the pop
	if dt < appear:
		return
	var fade := clampf((dt - appear) / 0.25, 0.0, 1.0)
	var s: float = bl["scale"]
	var popped: bool = bl["state"] == "pop" and dt >= 0.0
	if popped and dt > 0.3:
		return
	if popped:
		dt = 0.0
	var p: Vector2 = bl["pos"] + bl["vel"] * s * dt + Vector2(sin(v * 1.7 + bl["sway"]) * 6.0 * s, 0)
	if p.y < -80.0 or p.x < -80.0 or p.y > VP.y + 200.0:
		return
	var col: Color = bl["col"]
	if popped:
		var k: float = (v - bl["hit_v"]) / 0.3
		for i in 8:
			var d := Vector2.from_angle(TAU * i / 8.0 + bl["sway"])
			draw_line(p + d * (14.0 + 40.0 * k) * s, p + d * (24.0 + 50.0 * k) * s, Color(col, 1.0 - k), 4.0 * s)
		return
	var r := 26.0 * s
	var ink := Color(INK, fade)
	draw_line(p + Vector2(0, r * 1.2), p + Vector2(sin(v * 2.0 + bl["sway"]) * 8.0 * s, r * 1.2 + 60.0 * s),
		Color(INK, 0.6 * fade), 1.5)
	_ellipse(p, Vector2(r + 2.5, r * 1.2 + 2.5), ink)
	_ellipse(p, Vector2(r, r * 1.2), Color(col, fade))
	_ellipse(p + Vector2(-r * 0.35, -r * 0.45), Vector2(r * 0.22, r * 0.32), Color(1, 1, 1, 0.45 * fade))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-5, r * 1.2 + 6) * Vector2(s, 1),
		p + Vector2(5 * s, r * 1.2 + 6), p + Vector2(0, r * 1.2)]), ink)


func _draw_shadow(p: Vector2, s: float) -> void:
	_ellipse(p, Vector2(30, 7) * s, Color(0.25, 0.12, 0.1, 0.25))


func _draw_boomerang(p: Vector2, rot: float, s: float, col: Color) -> void:
	var pts := PackedVector2Array([Vector2(-30, 10), Vector2(-6, -16), Vector2(6, -16),
		Vector2(30, 10), Vector2(22, 16), Vector2(0, -2), Vector2(-22, 16)])
	draw_set_transform(p, rot, Vector2.ONE * s)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_colored_polygon(pts, col)
	draw_polyline(outline, Color(INK, col.a), 3.0)
	draw_line(Vector2(-22, 6), Vector2(-4, -10), Color(1, 1, 1, 0.35 * col.a), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- drawing ---------------------------------------------------------------------

func _draw() -> void:
	var v := Conductor.visual_position if _phase != Phase.CARD else 0.0
	var pulse := 0.0
	if _phase == Phase.PLAY:
		pulse = exp(-fposmod(Conductor.song_position_in_beats, 1.0) * 5.0)
	_draw_backdrop(pulse)
	var in_hand := _in_hand(v)
	_draw_thrower(v, in_hand)
	for bl in _balloons:
		_draw_balloon(bl, v)
	for b in _booms:
		if b["state"] in ["out", "bonk"] and v >= b["depart_v"]:
			_draw_flying(b, v)
	_draw_board(v)
	for p in _pops:
		var k := clampf((v - p["v0"]) / 0.7, 0.0, 1.0)
		if v >= p["v0"]:
			_text(p["text"], p["pos"] + Vector2(0, -30 * k), 28, Color(p["col"], 1.0 - k), false, 1.0 - k)
	_draw_hud()
	if _phase == Phase.CARD:
		_draw_card()
	elif _phase == Phase.DONE:
		_draw_results()


## Which boomerang (colour) is in your hand right now, or "" if it's out flying.
func _in_hand(v: float) -> String:
	if _phase == Phase.CARD:
		return "three"
	var shown := "three"
	for b in _booms:
		var st: String = b["state"]
		if st in ["out", "bonk"] and v >= b["depart_v"]:
			if st == "out" or v - b["miss_v"] < 0.6:
				return ""                  # still flying (or still bouncing off your head)
		if st == "caught" and v >= b["depart_v"]:
			shown = b["kind"]
		# the next one swaps in when its call starts, so you can see what's coming
		if v >= b["call_t"] + Conductor.video_offset:
			shown = b["kind"]
	return shown


func _draw_backdrop(pulse: float) -> void:
	draw_polygon(PackedVector2Array([Vector2(-20, -20), Vector2(VP.x + 20, -20),
		Vector2(VP.x + 20, HORIZON), Vector2(-20, HORIZON)]),
		PackedColorArray([SKY_TOP, SKY_TOP, SKY_LOW, SKY_LOW]))
	var sun := Vector2(820, HORIZON - 40)
	draw_circle(sun, 96 + 8 * pulse, Color(1, 0.85, 0.5, 0.25))
	draw_circle(sun, 74, Color(1, 0.88, 0.55))
	# mesas on the horizon
	var mesa := Color(0.55, 0.3, 0.32)
	draw_colored_polygon(PackedVector2Array([Vector2(560, HORIZON), Vector2(600, HORIZON - 70),
		Vector2(720, HORIZON - 72), Vector2(750, HORIZON)]), mesa)
	draw_colored_polygon(PackedVector2Array([Vector2(930, HORIZON), Vector2(960, HORIZON - 44),
		Vector2(1080, HORIZON - 46), Vector2(1120, HORIZON)]), mesa.lightened(0.08))
	draw_colored_polygon(PackedVector2Array([Vector2(60, HORIZON), Vector2(90, HORIZON - 34),
		Vector2(170, HORIZON - 36), Vector2(200, HORIZON)]), mesa.lightened(0.12))
	draw_polygon(PackedVector2Array([Vector2(-20, HORIZON), Vector2(VP.x + 20, HORIZON),
		Vector2(VP.x + 20, VP.y + 20), Vector2(-20, VP.y + 20)]),
		PackedColorArray([SAND.lightened(0.15), SAND.lightened(0.15), SAND, SAND]))
	for sb in [Vector3(420, 470, 0.6), Vector3(700, 492, 0.8), Vector3(1010, 520, 1.0), Vector3(540, 560, 1.2)]:
		_ellipse(Vector2(sb.x, sb.y), Vector2(26, 12) * sb.z, Color(0.5, 0.52, 0.3))
		_ellipse(Vector2(sb.x - 8 * sb.z, sb.y - 6 * sb.z), Vector2(14, 9) * sb.z, Color(0.58, 0.6, 0.34))


func _draw_thrower(v: float, in_hand: String) -> void:
	var k: float = v - _swing["v"]
	var arm := 0.0                     # arm angle offset (negative = up / forward)
	var lean := 0.0
	match _swing["kind"]:
		"throw":
			if k >= 0.0 and k < 0.3:
				arm = -1.3 * pow(1.0 - k / 0.3, 2.0)
				lean = 8.0 * (1.0 - k / 0.3)
		"catch":
			if k >= 0.0 and k < 0.22:
				arm = -0.45 * (1.0 - k / 0.22)
				lean = -6.0 * (1.0 - k / 0.22)
		"whiff":
			if k >= 0.0 and k < 0.18:
				arm = -0.6 * sin(PI * k / 0.18)
		"fumble":
			if k >= 0.0 and k < 0.4:
				arm = 0.4 * sin(PI * k / 0.4)
	var hurt := v - _bonk_v < 0.9
	if hurt:
		lean -= 10.0 * maxf(0.0, 1.0 - (v - _bonk_v) / 0.5)
	# calling: mouth open + a little head bob on each cue noise
	var call := 0.0
	if _phase == Phase.PLAY:
		for b in _booms:
			for ct in b["cues"]:
				var d: float = v - (float(ct) + Conductor.video_offset)
				if d >= 0.0 and d < 0.18:
					call = maxf(call, 1.0 - d / 0.18)
	var sh := Vector2(lean, -6.0 * call)
	_ellipse(FEET + Vector2(0, 8), Vector2(54, 10), Color(0.25, 0.12, 0.1, 0.25))
	# legs
	draw_line(BODY + Vector2(-14, 40), FEET + Vector2(-16, 0), INK, 9.0)
	draw_line(BODY + Vector2(14, 40), FEET + Vector2(16, 0), INK, 9.0)
	# body (khaki shirt)
	_ellipse(BODY + sh * 0.5, Vector2(42, 54), INK)
	_ellipse(BODY + sh * 0.5, Vector2(38, 50), Color(0.78, 0.68, 0.45))
	# back arm
	draw_line(SHOULDER + Vector2(-46, 0) + sh * 0.6, BODY + Vector2(-50, 30) + sh * 0.5, INK, 10.0)
	# head + bush hat
	var hp := HEAD + sh
	draw_circle(hp, 34, INK)
	draw_circle(hp, 31, Color(0.96, 0.78, 0.6))
	_ellipse(hp + Vector2(0, -22), Vector2(52, 9), Color(0.5, 0.36, 0.22))
	_ellipse(hp + Vector2(0, -34), Vector2(30, 16), Color(0.56, 0.4, 0.25))
	if hurt:
		_text("x", hp + Vector2(4, 4), 22, INK)
		_text("x", hp + Vector2(18, 4), 22, INK)
		var a := (v - _bonk_v) * 7.0
		for i in 3:
			var sp := hp + Vector2(0, -46) + Vector2.from_angle(a + TAU * i / 3.0) * Vector2(36, 10)
			_star(sp, 8.0, Color(1, 0.9, 0.3))
	else:
		draw_circle(hp + Vector2(10, -2), 4, INK)
		draw_circle(hp + Vector2(24, -2), 4, INK)
		if call > 0.0:
			_ellipse(hp + Vector2(17, 13), Vector2(6, 4 + 6 * call), INK)
		else:
			draw_arc(hp + Vector2(16, 10), 8, 0.2, PI - 0.2, 8, INK, 2.5)
	# throwing arm
	var hand := SHOULDER + sh * 0.6 + (HAND - SHOULDER).rotated(arm)
	draw_line(SHOULDER + sh * 0.6, hand, INK, 11.0)
	draw_line(SHOULDER + sh * 0.6, hand, Color(0.96, 0.78, 0.6), 6.0)
	if in_hand != "":
		_draw_boomerang(hand + Vector2(8, -6), -0.5 + arm, 0.9, TYPES[in_hand]["col"])
	draw_circle(hand, 9, INK)
	draw_circle(hand, 6.5, Color(0.96, 0.78, 0.6))


## The count for the boomerang that's up next / in the air, laid out in time:
## THROW  1  2  3  CATCH -- each word lights up on its beat.
func _draw_board(v: float) -> void:
	if _phase != Phase.PLAY:
		return
	var spb := Conductor.seconds_per_beat
	for b in _booms:
		if not b["board"]:
			continue
		var show_from: float = b["call_t"] + Conductor.video_offset
		var show_to: float = b["catch_t"] + 1.0 * spb + Conductor.video_offset
		if v < show_from or v > show_to:
			continue
		var a := clampf(minf((v - show_from) / 0.15, (show_to - v) / 0.25), 0.0, 1.0)
		var ty: Dictionary = TYPES[b["kind"]]
		var col: Color = ty["col"]
		var total: float = ty["catch"]
		var r := Rect2(166, 22, 820, 78)   # wide enough that the last "&" clears CATCH
		draw_rect(r.grow(4), Color(INK, a))
		draw_rect(r, Color(1, 0.97, 0.88, a))
		var base: float = b["throw_t"]
		var words: Array = [[0.0, "THROW"]]
		words.append_array(ty["counts"])
		words.append([total, "CATCH"])
		for w in words:
			var off: float = w[0]
			var label: String = w[1]
			var x := r.position.x + 70.0 + off / total * (r.size.x - 140.0)
			var t: float = base + off * spb + Conductor.video_offset
			var lit := v >= t
			var big := label == "THROW" or label == "CATCH"
			var flash := maxf(0.0, 1.0 - (v - t) / 0.2) if lit else 0.0
			var size := 26 if big else (22 if label == "&" else 34)
			size += int(8.0 * flash)
			var c := col if lit else Color(0.6, 0.55, 0.5)
			if big:
				var bw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 18.0
				var box := Rect2(x - bw / 2.0, r.position.y + 16, bw, 46)
				draw_rect(box, Color(c, a * (0.9 if lit else 0.25)))
				_text(label, Vector2(x, r.position.y + 50), size, Color(1, 1, 1, a) if lit else Color(INK, a), true)
			else:
				_text(label, Vector2(x, r.position.y + 52), size, Color(c, a), true)


func _draw_hud() -> void:
	_text("SPACE  throw / catch", Vector2(VP.x - 250, VP.y - 22), 18, Color(1, 1, 1, 0.9), false, 0.6)


func _draw_card() -> void:
	_panel(Rect2(206, 110, 740, 400))
	_text("BOOMERANG", Vector2(576, 168), 40, INK, true)
	_text("SPACE on THROW to throw it.  SPACE on CATCH to catch it.", Vector2(576, 220), 22, INK, true)
	_text("Cue, cue, THROW!  Each colour has its own cue. Catch right after the count:", Vector2(576, 254), 20, INK.lightened(0.25), true)
	var rows := [["three", "1   2   3   CATCH"], ["and", "1 & 2 & 3 & CATCH"], ["four", "1   2   3   4   CATCH"]]
	var y := 312.0
	for row in rows:
		var col: Color = TYPES[row[0]]["col"]
		_draw_boomerang(Vector2(330, y - 8), -0.4, 0.8, col)
		_text(row[1], Vector2(400, y), 28, col.darkened(0.15))
		y += 52.0
	_text("Watch the colour of the boomerang in your hand -- blue waits for the 4!",
		Vector2(576, 470), 18, INK.lightened(0.3), true)
	_text("SPACE to start", Vector2(576, 498), 18, INK.lightened(0.4), true)


func _draw_results() -> void:
	_panel(Rect2(326, 150, 500, 320))
	_text("WHAT A THROW!" if _tally["Miss"] <= 5 else "BONKED A FEW TIMES", Vector2(576, 210), 32, INK, true)
	var got: int = _tally["Perfect"] + _tally["Good"]
	Results.draw(self, _font, Vector2(576, 270), got, got + _tally["Miss"], INK, true)
	_text("SPACE / R to play again   -   Esc for menu", Vector2(576, 440), 18, INK.lightened(0.4), true)


# --- helpers ---------------------------------------------------------------------

func _text(t: String, pos: Vector2, size: int, col: Color, centred := false, outline := 0.0) -> void:
	if centred:
		var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		pos.x -= w / 2.0
	if outline > 0.0:
		draw_string_outline(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 7, Color(INK, outline * col.a))
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


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2.from_angle(-PI / 2.0 + TAU * i / 10.0) * rr)
	draw_colored_polygon(pts, col)


func _play(key: String, db: float) -> AudioStreamPlayer:
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = _sfx[key]
	p.volume_db = db
	p.play()
	return p


# --- placeholder sounds ------------------------------------------------------------

## Woodblock-ish tick for the counts (higher number = higher pitch). Starts on
## its very first sample so it lands on the beat.
func _synth_tick(freq: float, dur: float, amp: float, soft := false) -> AudioStreamWAV:
	const RATE := 44100
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in n:
		var t := float(i) / RATE
		var s := sin(TAU * freq * t) * exp(-t * (18.0 if soft else 32.0))
		s += 0.35 * sin(TAU * freq * 2.71 * t) * exp(-t * 70.0)
		s += rng.randf_range(-1.0, 1.0) * 0.3 * exp(-t * 400.0)
		buf[i] = s * amp
	return _to_wav(buf, RATE, amp)


## Placeholder cue "voice": a short sung vowel. Harmonics of f0 shaped by two
## formant bumps (f1, f2) pick the vowel. Hard attack so it lands on the beat.
func _synth_vowel(f0: float, f1: float, f2: float) -> AudioStreamWAV:
	const RATE := 44100
	const DUR := 0.2
	var n := int(DUR * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var amps := PackedFloat32Array()
	var k := 1
	while k * f0 < 5000.0:
		var h := k * f0
		amps.append(exp(-pow((h - f1) / 160.0, 2.0)) + 0.6 * exp(-pow((h - f2) / 220.0, 2.0)) + 0.05 / k)
		k += 1
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * f0 * (1.0 - 0.08 * t / DUR) / RATE     # a little downward "hup" inflection
		var s := 0.0
		for j in amps.size():
			s += amps[j] * sin(ph * (j + 1))
		buf[i] = s * minf(1.0, t * 400.0) * exp(-t * 14.0)
	return _to_wav(buf, RATE, 0.9)


## Balloon pop: a sharp bright crack that dies almost instantly.
func _synth_pop() -> AudioStreamWAV:
	const RATE := 44100
	var n := int(0.12 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var nz := rng.randf_range(-1.0, 1.0)
		lp += 0.25 * (nz - lp)
		buf[i] = (nz - lp) * exp(-t * 90.0) + sin(TAU * 900.0 * t) * 0.3 * exp(-t * 60.0)
	return _to_wav(buf, RATE, 0.95)


## Throw whoosh / whiff: band of noise sweeping up.
func _synth_whoosh(dur: float, seed_add: float) -> AudioStreamWAV:
	const RATE := 44100
	var n := int(dur * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9 + int(seed_add * 100.0)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var nz := rng.randf_range(-1.0, 1.0)
		var cut := 0.03 + 0.35 * u
		lp += cut * (nz - lp)
		lp2 += cut * (lp - lp2)
		buf[i] = (lp - lp2) * 2.0 * sin(PI * pow(u, 0.5)) * minf(1.0, t * 500.0)
	return _to_wav(buf, RATE, 0.9)


## Fallback catch: a short hand-slap thump (the monkey level's catch.wav is used if present).
func _synth_thump() -> AudioStreamWAV:
	const RATE := 44100
	var n := int(0.14 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * lerpf(200.0, 80.0, t / 0.14) / RATE
		buf[i] = sin(ph) * exp(-t * 30.0) + rng.randf_range(-1.0, 1.0) * exp(-t * 200.0) * 0.6
	return _to_wav(buf, RATE, 0.95)


## Cartoon bonk: hollow knock with a wobbly "boing".
func _synth_bonk() -> AudioStreamWAV:
	const RATE := 44100
	var n := int(0.45 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var ph2 := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * 520.0 * exp(-t * 3.0) / RATE
		ph2 += TAU * (240.0 + 60.0 * sin(TAU * 14.0 * t)) / RATE
		buf[i] = sin(ph) * exp(-t * 25.0) + 0.6 * sin(ph2) * exp(-t * 6.0) * minf(1.0, t * 200.0)
	return _to_wav(buf, RATE, 0.95)


## Normalise to `peak_to` of full scale and pack as 16-bit mono.
func _to_wav(buf: PackedFloat32Array, rate: int, peak_to: float) -> AudioStreamWAV:
	var peak := 0.0001
	for x in buf:
		peak = maxf(peak, absf(x))
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] / peak * peak_to, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
