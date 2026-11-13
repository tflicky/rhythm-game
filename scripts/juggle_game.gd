extends Node2D
## "Juggling" (prototype). You keep a juggle going: every press is one hand
## catching while the other throws, so you hold a steady rhythm all through a
## section. Three sections, each with its own (slightly altered) rhythm:
##   1. tennis balls, in the backyard
##   2. bowling pins, on a unicycle
##   3. flaming swords, on a trapeze over a shark tank
## The CALL: before each section the juggler shows you its rhythm for one bar
## ("hup" on every catch); then you take over. A second call ("stop") comes on the
## downbeat of the section's last bar: finish that bar and he holds everything.
## Between sections the curtain closes and opens on the next act.
##   Space / left click  catch + throw     Enter start     R restart     Esc pause
##
## The sections are data in SECTIONS (beats are on the song's grid), so changing
## a rhythm or moving a section is a one-line edit. Art is yours to draw: see
## ART below -- until a file exists, a plain labelled box stands in. Sounds go in
## res://audio/sfx/juggle/ (see SFX_SLOTS); until then simple placeholders play.

enum Phase { CARD, PLAY, DONE }

const VP := Vector2(1152, 648)
const PERFECT := 0.07
const GOOD := 0.14
const MISS_TAIL := 0.03
const INK := Color(0.2, 0.14, 0.12)
const OBJECTS := 3                 ## things in the air; each one lands OBJECTS catches after it's thrown

## Each section: its stage, what's juggled, the beat the call bar starts on (you
## take over one bar later), how many bars you play, and the catch rhythm within
## each bar (beats from the bar's start). The juggler plays the call bar himself.
const SECTIONS := [
	{"stage": "backyard", "prop": "tennis_ball", "call": 4.0, "bars": 8,
		"rhythm": [0.0, 1.0, 2.0, 3.0]},                   # 1  2  3  4
	{"stage": "unicycle", "prop": "bowling_pin", "call": 52.0, "bars": 8,
		"rhythm": [0.0, 1.0, 2.0, 2.5, 3.0]},              # 1  2  3 & 4
	{"stage": "trapeze", "prop": "flaming_sword", "call": 100.0, "bars": 8,
		"rhythm": [0.0, 1.0, 1.5, 2.0, 3.0, 3.5]},         # 1  2 & 3  4 &
]
const CURTAIN_BEATS := 2.0         ## curtain closing (and again opening) in a break

## Your drawings, in res://art/juggling/ (PNG, transparent background). Until a
## file exists a labelled box is drawn in its place.
const ART_DIR := "res://art/juggling/"
const ART := ["backyard", "shark_tank", "shark", "juggler", "unicycle", "trapeze",
	"tennis_ball", "bowling_pin", "flaming_sword", "curtain"]

## Sounds, in res://audio/sfx/juggle/ named after the slot (.wav / .ogg / .mp3).
const SFX_DIR := "res://audio/sfx/juggle/"
const SFX_SLOTS := ["call", "stop_call", "catch", "drop", "curtain"]

## --- layout (screen px) -------------------------------------------------------
const GROUND_Y := 560.0
const STAND := Vector2(576, 560)        ## feet, standing in the backyard
const UNI_LIFT := 110.0                 ## how much higher he is on the unicycle
const PIVOT := Vector2(576, -10)        ## trapeze ropes hang from here
const ROPE := 330.0
const SWING := 0.2                      ## trapeze swing (radians each way), over 2 bars
const HAND_SPREAD := 62.0
const BODY_SIZE := Vector2(130, 190)

@onready var audio: AudioStreamPlayer = $AudioStreamPlayer

var _font: Font
var _art := {}
var _sfx := {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _phase := Phase.CARD
var _events: Array = []        ## every catch, in order: { t, beat, sec, auto, state, idx, sounded }
var _sec_events: Array = []    ## per section: its events (for the throws' arcs)
var _stop_calls: Array = []    ## { t, sounded } -- the "last bar" call per section
var _drops: Array = []         ## missed: { pos, v0, prop }
var _tally := {"Perfect": 0, "Good": 0, "Miss": 0}
var _results: Results
var _pause: PauseMenu
var _flash_v := -10.0          ## last good catch (the juggler pops a little)


func _ready() -> void:
	_pause = PauseMenu.attach(self, _start)   # Esc: Continue / Retry / Quit
	_results = Results.new()
	add_child(_results)
	_font = ThemeDB.fallback_font
	for a in ART:
		var path := "%s%s.png" % [ART_DIR, a]
		if ResourceLoader.exists(path):
			_art[a] = load(path)
	for slot in SFX_SLOTS:
		_sfx[slot] = _load_sfx(slot)
	for i in 10:
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


func _load_sfx(slot: String) -> AudioStream:
	for ext in ["wav", "ogg", "mp3"]:
		var path := "%s%s.%s" % [SFX_DIR, slot, ext]
		if ResourceLoader.exists(path):
			return load(path)
	match slot:      # placeholders until your sounds exist
		"call": return _synth_vowel(180.0, 650.0, 1100.0)                 # "hup"
		"stop_call": return _synth_whistle()
		"catch":
			if ResourceLoader.exists("res://audio/sfx/catch.wav"):        # the monkey level's thunk
				return load("res://audio/sfx/catch.wav")
			return _synth_thump()
		"drop": return _synth_thump()
	return null


# --- flow ------------------------------------------------------------------------

func _start() -> void:
	Conductor.stop()
	_events.clear()
	_sec_events.clear()
	_stop_calls.clear()
	_drops.clear()
	_tally = {"Perfect": 0, "Good": 0, "Miss": 0}
	if _results:
		_results.reset()
	for si in SECTIONS.size():
		var s: Dictionary = SECTIONS[si]
		var list: Array = []
		for bar in int(s["bars"]) + 1:            # bar 0 = the juggler's call bar
			for off in s["rhythm"]:
				var beat: float = s["call"] + bar * 4.0 + off
				var e := {"t": Conductor.time_of_beat(beat), "beat": beat, "sec": si,
					"auto": bar == 0, "state": "auto" if bar == 0 else "wait",
					"idx": list.size(), "sounded": false}
				list.append(e)
				_events.append(e)
		_sec_events.append(list)
		var last_bar: float = s["call"] + float(s["bars"]) * 4.0
		_stop_calls.append({"t": Conductor.time_of_beat(last_bar), "sounded": false})
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


## One press = one catch (and the throw that goes with it): the nearest waiting catch.
func _press() -> void:
	var adj := Conductor.live_position() - Conductor.input_offset
	var best: Dictionary = {}
	var best_err := INF
	for e in _events:
		if e["state"] != "wait":
			continue
		var err: float = adj - e["t"]
		if err < -GOOD:
			break                       # the rest are later still
		if absf(err) <= GOOD and absf(err) < absf(best_err):
			best = e
			best_err = err
	if best.is_empty():
		return                          # nothing to catch: a harmless grab at the air
	best["state"] = "hit"
	var grade := "Perfect" if absf(best_err) <= PERFECT else "Good"
	_tally[grade] += 1
	_flash_v = Conductor.visual_position
	_play("catch", 0.0)


func _process(_dt: float) -> void:
	if _phase == Phase.PLAY:
		var now := Conductor.song_position
		var lat := AudioServer.get_output_latency()
		for e in _events:
			# the juggler's call bar: his catches, each with a "hup", on the beat
			if e["auto"] and not e["sounded"] and now >= e["t"] - lat:
				e["sounded"] = true
				_play("call", -2.0)
				_play("catch", -4.0)
			# your catch that never came: it drops
			if e["state"] == "wait" and now > e["t"] + Conductor.input_offset + GOOD + MISS_TAIL:
				e["state"] = "miss"
				_tally["Miss"] += 1
				_drops.append({"pos": _hand(e["idx"] % 2, Conductor.visual_position, e["sec"]),
					"v0": Conductor.visual_position, "sec": e["sec"]})
				_play("drop", -4.0)
		for sc in _stop_calls:
			if not sc["sounded"] and now >= sc["t"] - lat:
				sc["sounded"] = true
				_play("stop_call", 0.0)
		_drops = _drops.filter(func(d): return Conductor.visual_position - d["v0"] < 1.5)
	queue_redraw()


# --- where things are --------------------------------------------------------------

func _beat_at(v: float) -> float:
	return (v - Conductor.first_beat_offset) / Conductor.seconds_per_beat


## Which section's stage is showing at visual time v: it switches while the
## curtain is shut, halfway between one section's end and the next one's call.
func _section_at(v: float) -> int:
	var b := _beat_at(v)
	var si := 0
	for i in range(1, SECTIONS.size()):
		if b >= _switch_beat(i):
			si = i
	return si


func _section_end(i: int) -> float:
	var s: Dictionary = SECTIONS[i]
	return s["call"] + (float(s["bars"]) + 1.0) * 4.0


func _switch_beat(i: int) -> float:
	return (_section_end(i - 1) + float(SECTIONS[i]["call"])) * 0.5


## How shut the curtain is (0 open .. 1 shut) at visual time v.
func _curtain(v: float) -> float:
	var b := _beat_at(v)
	for i in range(1, SECTIONS.size()):
		var mid := _switch_beat(i)
		var half: float = (float(SECTIONS[i]["call"]) - _section_end(i - 1)) * 0.5
		var d := absf(b - mid)
		if d < half:
			return clampf((half - d) / CURTAIN_BEATS, 0.0, 1.0)
	return 0.0


## The juggler's body centre (and lean) at visual time v, for the stage of section si.
func _body(v: float, si: int) -> Dictionary:
	var b := _beat_at(v)
	var ph := fposmod(b, 1.0)
	match SECTIONS[si]["stage"]:
		"unicycle":   # up on the seat, bobbing on every beat
			var bob := -6.0 * sin(ph * PI)
			return {"pos": STAND + Vector2(0, -BODY_SIZE.y * 0.5 - UNI_LIFT + bob), "rot": 0.04 * sin(b * PI * 0.5)}
		"trapeze":    # sitting on the bar, swinging over the tank
			var a := SWING * sin(b * PI / 4.0)
			var seat := PIVOT + Vector2(sin(a), cos(a)) * ROPE
			return {"pos": seat + Vector2(0, -BODY_SIZE.y * 0.5 + 12.0).rotated(-a), "rot": -a, "seat": seat, "a": a}
	return {"pos": STAND + Vector2(0, -BODY_SIZE.y * 0.5), "rot": 0.0}


## Hand `side` (0 left, 1 right) at visual time v.
func _hand(side: int, v: float, si: int) -> Vector2:
	var bd := _body(v, si)
	var off := Vector2((-1.0 if side == 0 else 1.0) * HAND_SPREAD, 10.0).rotated(bd["rot"])
	return bd["pos"] + off


## Where object `o` of section si is at visual time v, plus its spin.
## Catch i throws its object up; it comes down OBJECTS catches later in the other
## hand. Before its first throw it waits in a hand; after the last catch it stays held.
func _object(si: int, o: int, v: float) -> Dictionary:
	var list: Array = _sec_events[si]
	var shift := Conductor.input_offset    # drawn to land when a perfect press registers
	var last := -1
	for e in list:
		if e["idx"] % OBJECTS == o and e["t"] + shift <= v:
			last = e["idx"]
	if last < 0:     # not thrown yet: resting in a hand
		return {"pos": _hand(o % 2, v, si) + Vector2(0, -8.0 - 10.0 * o), "rot": 0.0}
	var nxt := last + OBJECTS
	if nxt >= list.size():   # caught for the last time: held
		return {"pos": _hand(last % 2, v, si) + Vector2(0, -10.0), "rot": 0.0}
	var t0: float = list[last]["t"] + shift
	var t1: float = list[nxt]["t"] + shift
	var u := clampf((v - t0) / maxf(t1 - t0, 0.01), 0.0, 1.0)
	var p0 := _hand(last % 2, t0, si)
	var p1 := _hand(nxt % 2, t1, si)
	var beats := (t1 - t0) / Conductor.seconds_per_beat
	var h := 70.0 + 55.0 * beats
	return {"pos": p0.lerp(p1, u) + Vector2(0, -h * 4.0 * u * (1.0 - u)), "rot": u * TAU * (1.0 + floorf(beats))}


# --- drawing -----------------------------------------------------------------------

func _draw() -> void:
	var v := Conductor.visual_position if _phase != Phase.CARD else 0.0
	var si := _section_at(v)
	_draw_stage(si, v)
	_draw_juggler(si, v)
	if _phase != Phase.CARD:
		for o in OBJECTS:
			var ob := _object(si, o, v)
			_draw_prop(SECTIONS[si]["prop"], ob["pos"], ob["rot"])
		for d in _drops:    # a missed one falls away
			var t: float = v - d["v0"]
			_draw_prop(SECTIONS[d["sec"]]["prop"], d["pos"] + Vector2(30.0 * t, 900.0 * t * t), t * 9.0, 1.0 - t / 1.5)
	var c := _curtain(v)
	if c > 0.0:
		_draw_curtain(c)
	if _phase == Phase.CARD:
		_draw_card()
	elif _phase == Phase.DONE:
		_draw_results()


func _draw_stage(si: int, v: float) -> void:
	var stage: String = SECTIONS[si]["stage"]
	if stage == "trapeze":
		draw_rect(Rect2(Vector2.ZERO, VP), Color(0.16, 0.14, 0.24))          # a big dark tent
		_box("shark_tank", Rect2(170, 470, 812, 190), Color(0.25, 0.55, 0.8, 0.85))
		# the shark: a fin patrolling the tank
		var fx := 576.0 + 300.0 * sin(_beat_at(v) * PI / 8.0)
		var dir := 1.0 if cos(_beat_at(v) * PI / 8.0) > 0.0 else -1.0
		if _art.has("shark"):
			_box("shark", Rect2(fx - 60, 455, 120, 70), Color.TRANSPARENT)
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(fx - 26 * dir, 500), Vector2(fx + 22 * dir, 500), Vector2(fx - 6 * dir, 452)]), Color(0.35, 0.4, 0.45))
		var bd := _body(v, si)
		var seat: Vector2 = bd["seat"]
		var a: float = bd["a"]
		var across := Vector2(cos(a), -sin(a)) * 70.0
		draw_line(PIVOT + Vector2(-70, 0), seat - across, Color(0.85, 0.8, 0.7), 3.0)
		draw_line(PIVOT + Vector2(70, 0), seat + across, Color(0.85, 0.8, 0.7), 3.0)
		_box("trapeze", Rect2(seat - Vector2(80, 8), Vector2(160, 16)), Color(0.75, 0.6, 0.3))
		return
	# the backyard (sections 1 and 2)
	draw_rect(Rect2(0, 0, VP.x, GROUND_Y), Color(0.62, 0.82, 0.95))
	draw_rect(Rect2(0, GROUND_Y - 120, VP.x, VP.y), Color(0.45, 0.7, 0.35))
	_box("backyard", Rect2(0, 0, VP.x, VP.y), Color.TRANSPARENT)
	if stage == "unicycle":
		var bd := _body(v, si)
		var seat: Vector2 = bd["pos"] + Vector2(0, BODY_SIZE.y * 0.5)
		_box("unicycle", Rect2(seat.x - 40, seat.y, 80, STAND.y - seat.y), Color(0.85, 0.3, 0.3))


func _draw_juggler(si: int, v: float) -> void:
	var bd := _body(v, si)
	var pop := 1.0 + 0.06 * clampf(1.0 - (v - _flash_v) / 0.12, 0.0, 1.0)
	draw_set_transform(bd["pos"], bd["rot"], Vector2(pop, pop))
	_box("juggler", Rect2(-BODY_SIZE * 0.5, BODY_SIZE), Color(0.95, 0.85, 0.7))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for side in 2:
		draw_circle(_hand(side, v, si), 9.0, Color(0.95, 0.8, 0.65))
		draw_arc(_hand(side, v, si), 9.0, 0.0, TAU, 20, INK, 2.0)


## A ball / pin / sword at p, spun by rot. Your drawing if it exists, else a plain shape.
func _draw_prop(prop: String, p: Vector2, rot: float, alpha := 1.0) -> void:
	if alpha <= 0.0:
		return
	draw_set_transform(p, rot, Vector2.ONE)
	if _art.has(prop):
		var tex: Texture2D = _art[prop]
		var sz := tex.get_size() * (56.0 / maxf(tex.get_size().x, tex.get_size().y))
		draw_texture_rect(tex, Rect2(-sz * 0.5, sz), false, Color(1, 1, 1, alpha))
	else:
		match prop:
			"tennis_ball":
				draw_circle(Vector2.ZERO, 11.0, Color(0.8, 0.95, 0.2, alpha))
				draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 20, Color(INK, alpha), 2.0)
			"bowling_pin":
				draw_rect(Rect2(-6, -24, 12, 48), Color(0.97, 0.97, 0.95, alpha))
				draw_rect(Rect2(-6, -10, 12, 5), Color(0.85, 0.2, 0.2, alpha))
				draw_rect(Rect2(-6, -24, 12, 48), Color(INK, alpha), false, 2.0)
			"flaming_sword":
				draw_line(Vector2(0, 22), Vector2(0, -30), Color(0.8, 0.82, 0.88, alpha), 5.0)
				draw_line(Vector2(-9, 14), Vector2(9, 14), Color(0.55, 0.4, 0.2, alpha), 5.0)
				draw_colored_polygon(PackedVector2Array([Vector2(-8, -22), Vector2(8, -22), Vector2(0, -46)]), Color(1.0, 0.55, 0.1, alpha))
				draw_colored_polygon(PackedVector2Array([Vector2(-4, -24), Vector2(4, -24), Vector2(0, -38)]), Color(1.0, 0.9, 0.3, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_curtain(c: float) -> void:
	var w := VP.x * 0.5 * c
	if _art.has("curtain"):
		_box("curtain", Rect2(0, 0, w, VP.y), Color.TRANSPARENT)
		_box("curtain", Rect2(VP.x - w, 0, w, VP.y), Color.TRANSPARENT)
		return
	draw_rect(Rect2(0, 0, w, VP.y), Color(0.6, 0.1, 0.12))
	draw_rect(Rect2(VP.x - w, 0, w, VP.y), Color(0.6, 0.1, 0.12))
	draw_line(Vector2(w, 0), Vector2(w, VP.y), INK, 4.0)
	draw_line(Vector2(VP.x - w, 0), Vector2(VP.x - w, VP.y), INK, 4.0)


## Your drawing `name` stretched into r, or (until it exists) a box filled with
## `fill` and a dashed outline with the name in it.
func _box(art_name: String, r: Rect2, fill: Color) -> void:
	if _art.has(art_name):
		draw_texture_rect(_art[art_name], r, false)
		return
	if fill.a > 0.0:
		draw_rect(r, fill)
	var dash := 10.0
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := int(a.distance_to(b) / dash)
		for k in range(0, n, 2):
			draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), Color(INK, 0.45), 2.0)
	draw_string(_font, Vector2(r.position.x, r.position.y + minf(r.size.y * 0.5, 28.0) + 6.0), art_name,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 16, Color(INK, 0.55))


func _draw_card() -> void:
	var r := Rect2(VP.x * 0.5 - 380, VP.y - 132, 760, 96)
	_panel(r)
	_text("Juggle!", Vector2(576, r.position.y + 38), 30, INK, true)
	_text("He shows you the rhythm first. Then press SPACE on every catch.", Vector2(576, r.position.y + 74), 22, Color(0.6, 0.32, 0.08), true)
	var blink := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 250.0)
	_text("SPACE", Vector2(r.end.x - 60, r.end.y - 12), 16, Color(INK, blink), true)


func _draw_results() -> void:
	var r := Rect2(VP.x * 0.5 - 180, VP.y * 0.5 - 110, 360, 220)
	_panel(r)
	var got: int = _tally["Perfect"] + _tally["Good"]
	_results.draw_percent(self, _font, r.get_center() + Vector2(0, -10), got, got + _tally["Miss"])
	_text("SPACE / R to play again   -   Esc for menu", Vector2(576, r.end.y - 18), 16, INK.lightened(0.4), true)


# --- helpers ---------------------------------------------------------------------

func _text(t: String, pos: Vector2, size: int, col: Color, centred := false) -> void:
	if centred:
		pos.x -= _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x / 2.0
	draw_string(_font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _panel(r: Rect2) -> void:
	draw_rect(r.grow(4), INK)
	draw_rect(r, Color(1, 0.97, 0.88))


func _play(key: String, db: float) -> void:
	if _sfx.get(key) == null:
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = _sfx[key]
	p.volume_db = db
	p.play()


## Placeholder "hup": a short sung vowel with a hard attack so it lands on the beat.
func _synth_vowel(f0: float, f1: float, f2: float) -> AudioStreamWAV:
	const RATE := 44100
	const DUR := 0.18
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
		ph += TAU * f0 * (1.0 - 0.08 * t / DUR) / RATE
		var s := 0.0
		for j in amps.size():
			s += amps[j] * sin(ph * (j + 1))
		buf[i] = s * minf(1.0, t * 400.0) * exp(-t * 14.0)
	return _to_wav(buf, RATE, 0.9)


## Placeholder "stop" call: a short two-note whistle, down.
func _synth_whistle() -> AudioStreamWAV:
	const RATE := 44100
	var n := int(0.32 * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 1760.0 if t < 0.14 else 1318.5
		ph += TAU * f / RATE
		buf[i] = sin(ph) * minf(1.0, t * 300.0) * (1.0 if t < 0.28 else (0.32 - t) / 0.04)
	return _to_wav(buf, RATE, 0.7)


## Placeholder catch / drop: a short hand-slap thump.
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
