extends Node2D
## "Wizard Tower" (prototype). Call and response: the enemy tower on the horizon
## launches a bar of fireballs / iceballs straight up into the sky; one bar later
## they come back down out of the sky at you in the same order and rhythm. Blast
## each one on its beat with the OPPOSITE element.
##   A / Left / left click     ICE spell   (freezes fireballs)
##   D / Right / right click   FIRE spell  (melts iceballs)
##   Space start   R restart   Esc menu
##   F2  record your own patterns (tap them in to the song, see _start_record)
##
## Art: art/wizard/*.png, exported from "wizard basics.kra" by tools/kra_export.ps1
## (at half size). Every frame keeps its place on the 3508x2480 Krita canvas
## (art/wizard/frames.json), so the wand, the spell and its burst line up exactly
## as drawn. The sky, hills, enemy tower and wall are placeholder drawings.

enum Phase { DEMO, CARD, PLAY, DONE, RECORD }

const VP := Vector2(1152, 648)
const PERFECT := 0.075
const GOOD := 0.15
const MISS_TAIL := 0.03
const EARLY := 0.3                 ## no spamming: a press this long before a ball (too early to hit it) wrecks it
const BOTH_AT_ONCE := 0.08         ## ICE and FIRE pressed this close together: the hit doesn't count
const TRAVEL_BEATS := 4.0          ## launch -> hit: exactly one bar later, same rhythm
const REC_END_LEEWAY := 0.75     ## record mode: a tap up to this many beats past the end of a call bar sticks to its last spot
## Flight: one arc from the enemy tower to the burst point, all on screen. The ball
## shoots up fast, hangs near the top of the sky (small and far away), then swoops
## at you, growing as it comes. Each beat of the bar gets its own lane across the
## sky, so a pattern hangs up there in order, like notes, before it comes down.
const APEX_Y := -40.0              ## height of the arc's control points (screen y)
const APEX_AT := 0.3               ## fraction of the flight spent climbing to the hang
const APEX_P := 0.45               ## how far along the path the hang point is
const LANE_SPREAD := 95.0          ## sideways spread per beat of the bar (screen px)
const MISS_FLY := 0.35             ## after a miss, seconds per "screen push" past the burst point
## The song: audio/music/Wizard_Song.wav. Measured from the audio: 110 BPM, the
## beat grid starts right at 0.0 s: the MIDI parts (bass, melody, organ, kalimba) all
## line up with the audio there. (It was 0.243 before, which put every beat half a beat late.)
## The song is written in 3-bar phrases (from the MIDI parts: melody, organ and bass
## all repeat every 3 bars, starting at DAW bar 4). Each pattern follows one phrase:
##   bar 1 call (wizard throws over the melody), bar 2 answer (you), bar 3 breather
##   (the melody finishes its sentence, nothing to hit).
## The kalimba intro is DAW bars 1-3, so the first call is DAW bar 4 (bar 3 counting from 0).
const SONG_BPM := 110.0
const SONG_OFFSET := 0.0
const FIRST_CALL_BAR := 3          ## the free intro plays out before the first pattern
const PATTERN_BARS := 3            ## bars per pattern: call, answer, breather
## Placeholder demo of the Rhythm Thief-style layout (tools/wizard_guide/make_demo.py):
## starts on the beat at 0:00, 4 intro bars + a get-ready bar, then call/answer pairs.
const DEMO_SONG := "res://audio/music/wizard_demo.ogg"
const DEMO_FIRST_CALL_BAR := 5
const DEMO_PATTERN_BARS := 2       ## the demo goes straight call, answer, call, answer

## Play the placeholder demo song instead of Wizard_Song.wav (to try the
## full-band call bar / thin answer bar idea). Untick to go back to your song.
@export var use_demo_song := false
## Before the title card, two practice shots over a click track: a fireball you
## freeze with ICE (A), then an iceball you melt with FIRE (D). Each repeats until
## you get it. SPACE skips straight into the game.
@export var show_demo := true
## Play the calls from your Call MIDI (audio/music/wizard_call.mid) instead of the
## PATTERNS list. Low notes (below E3) are fire balls, E3 and up are ice balls.
## Each note is answered 1 bar + answer_delay beats later, in the same rhythm (from my
## "where the response should be" MIDI: 1 bar + 1 1/3 beats). A call too long to
## finish first is answered whole bars later. Replace the file with a new export from
## your DAW to change the calls.
@export var use_call_midi := true
const CALL_MIDI := "res://audio/music/wizard_call.mid"
const CALL_FIRE_BELOW := 52        ## MIDI note E3: notes below it are fire, E3 and up are ice
const CALL_PHRASE_GAP := 4.0       ## more than this many beats between notes starts a new call
## Call MIDI: beats after the next bar's matching beat that the answer lands (4/3 = 1 1/3 beats).
@export_range(0.0, 3.99, 0.001) var answer_delay := 4.0 / 3.0
## Record mode (F2): taps snap to this grid. Triplet = thirds of a beat.
@export_enum("Off:0", "Quarter:1", "Eighth:2", "Triplet:3", "Sixteenth:4") var record_snap: int = 2

var _first_call_bar := FIRST_CALL_BAR
var _pattern_bars := PATTERN_BARS
## One entry per call bar: [beat in bar, element]. The answer is the next bar
## (then, with your song, a breather bar before the next call).
## If the song is too short for all of them, an even spread is used (always the
## first and the last), so it still builds up to the hardest ones.
const PATTERNS := [
	[[2, "fire"], [3.5, "ice"]],
	[[1.5, "ice"], [2, "ice"], [3.5, "fire"]],
	[[1.5, "fire"], [2, "fire"], [3.5, "ice"]],
	[[0, "fire"], [1.5, "ice"], [2, "ice"], [3.5, "fire"]],
	[[1.5, "ice"], [3, "ice"], [3.5, "fire"]],
	[[1.5, "fire"], [2, "fire"], [3.5, "ice"]],
	[[1, "ice"], [2.5, "ice"], [3.5, "ice"]],
	[[1, "fire"], [2.5, "fire"]],
	[[1, "ice"], [1.5, "fire"], [2, "ice"], [2.5, "fire"], [3, "ice"], [3.5, "ice"]],
]
var _patterns: Array = PATTERNS.duplicate(true)   ## what plays (record mode updates it live)
var _rec: Array = []               ## record mode: one list of [beat, element] per call bar
var _rec_undo: Array = []          ## pattern index of each tap, for Z
var _rec_msg := ""
var _rec_msg_t := -10.0

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
const PRACTICE_CLICK_BEATS := 256  ## practice metronome length (about 2 1/2 minutes at 110 BPM)
const WALK_IN := 3.0               ## seconds the gnome takes to walk up to his spot when the game starts
const WALK_FROM := Vector2(-330, 240)  ## where he walks in from (screen px, bottom left)
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

var _skip_btn: Button               ## phone: the Skip button during practice (null on a computer)
var _phase := Phase.CARD
var _song_stream: AudioStream      ## the level's song (the demo runs on a click track instead)
var _demo_end := 0.0               ## song time the practice shot is judged
var _demo_step := 0                ## 0 = fireball (press ICE), 1 = iceball (press FIRE)
var _demo_retry := false           ## the last try missed: show "Try again!"
var _demo_fails := 0               ## misses on this practice shot; after 2 the ball waits for you
var _frozen := false               ## practice: the ball is held at the burst point until you press
var _freeze_v := 0.0
var _balls: Array = []             ## { kind, launch_t, hit_t, arrive_v, state, ... }
var _spells: Array = []            ## { kind, t0, impact, fizzle }
var _pops: Array = []              ## { text, col, t0 } grade text by the burst
var _scars: Array = []             ## { kind, x } scorch / frost marks on your wall
var _cast_v := -10.0               ## visual time of the last cast (wand recoil)
var _last_cast := {}               ## { kind, t, ball, grade, spell } for the both-buttons check
var _hurt := {}                    ## { kind, v } last hit you took (flash + shake)
var _tally := {"Perfect": 0, "Good": 0, "Miss": 0}
var _results: Results          ## the counting-up percent on the results screen

var _impact_s: Vector2             ## burst point on screen
var _dir: Vector2                  ## comet travel direction on screen


var _pause: PauseMenu

func _ready() -> void:
	_pause = PauseMenu.attach(self, _start)   # Esc: Continue / Retry / Quit
	_skip_btn = TutorialUI.add_skip_button(self, _skip_practice)   # phone only
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
	_load_sfx_files()                  # your recordings replace the synth stand-ins
	for i in 16:                      # bursts ring ~1.5 s, so leave room for overlaps
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_play("cast_ice", -4.0)            # entering the level: the sound your press makes
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 90:
		_stars.append(Vector3(rng.randf() * VP.x, rng.randf() * (HORIZON - 30.0), rng.randf_range(0.8, 2.2)))

	_impact_s = _c2s(IMPACT)
	_dir = Vector2.from_angle(deg_to_rad(BALL_DIR_DEG))

	Conductor.stream_player = audio
	Conductor.bpm = SONG_BPM
	Conductor.first_beat_offset = SONG_OFFSET
	if use_demo_song and ResourceLoader.exists(DEMO_SONG):
		audio.stream = load(DEMO_SONG)
		audio.stream.loop = false
		Conductor.first_beat_offset = 0.0   # the demo starts right on the beat
		_first_call_bar = DEMO_FIRST_CALL_BAR
		_pattern_bars = DEMO_PATTERN_BARS
	Conductor.video_offset = 0.0
	Conductor.input_offset = Settings.input_offset(0.131)
	Conductor.song_finished.connect(_on_song_finished)
	_song_stream = audio.stream
	if show_demo:
		_start_demo()


## Practice shots: a click track, one ball launched after a bar of clicks that you
## blast a bar later. Step 0 is a fireball (ICE), step 1 an iceball (FIRE); a miss
## repeats the step, and after both comes the title card.
func _start_demo(step := 0, retry := false) -> void:
	_demo_step = step
	_demo_retry = retry
	if retry:
		_demo_fails += 1
	else:
		_demo_fails = 0
	_unfreeze()
	_balls.clear()
	_pops.clear()
	_hurt = {}
	var launch_beat := 4.0
	if _phase == Phase.DEMO and Conductor.playing:
		# the metronome keeps going: the next shot goes up on the next downbeat
		launch_beat = ceilf((Conductor.song_position_in_beats + 1.0) / 4.0) * 4.0
	else:
		Conductor.stop()
		_spells.clear()
		_cast_v = -10.0
		_phase = Phase.DEMO
		audio.stream = ClickTrack.make(Conductor.bpm, PRACTICE_CLICK_BEATS, Conductor.beats_per_measure, Conductor.first_beat_offset)
		audio.volume_db = -8.0
		Conductor.play()
	var hit_t := Conductor.time_of_beat(launch_beat + TRAVEL_BEATS)
	_balls.append({"kind": "fire" if step == 0 else "ice", "launch_t": Conductor.time_of_beat(launch_beat),
		"hit_t": hit_t, "arrive_v": hit_t + Conductor.input_offset,
		"lane": 0.0, "state": "fly", "launched": false, "impact": -1.0, "burst_sfx": null, "hurt": false})
	_balls[0]["hold"] = _demo_fails >= 2   # 3rd try: it stops and waits for the right button
	_demo_end = hit_t + 1.4


func _end_demo() -> void:
	_unfreeze()
	_cast_v = -10.0
	Conductor.stop()
	_balls.clear()
	_spells.clear()
	_pops.clear()
	_phase = Phase.CARD


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
	_unfreeze()
	_cast_v = -10.0
	Conductor.stop()
	audio.stream = _song_stream
	audio.volume_db = 0.0
	_balls.clear()
	_spells.clear()
	_pops.clear()
	_scars.clear()
	_hurt = {}
	_tally = {"Perfect": 0, "Good": 0, "Miss": 0}
	if _results:
		_results.reset()
	var chart := _call_chart() if use_call_midi else []
	if not chart.is_empty():
		for c in chart:
			var hit_t := Conductor.time_of_beat(c["hit"])
			_balls.append({"kind": c["kind"], "launch_t": Conductor.time_of_beat(c["beat"]),
				"hit_t": hit_t, "arrive_v": hit_t + Conductor.input_offset,
				"lane": fposmod(c["beat"], 4.0), "state": "fly", "launched": false, "impact": -1.0, "burst_sfx": null, "hurt": false})
	else:
		var bar := _first_call_bar
		for pat in _patterns_that_fit():
			for n in pat:
				var launch_beat: float = bar * 4 + float(n[0])
				var hit_t := Conductor.time_of_beat(launch_beat + TRAVEL_BEATS)
				_balls.append({"kind": n[1], "launch_t": Conductor.time_of_beat(launch_beat),
					"hit_t": hit_t, "arrive_v": hit_t + Conductor.input_offset,
					"lane": float(n[0]), "state": "fly", "launched": false, "impact": -1.0, "burst_sfx": null, "hurt": false})
			bar += _pattern_bars
	_phase = Phase.PLAY
	Conductor.play()


## The calls from the Call MIDI: [{beat, kind, hit}], beats counted from the song's
## first beat (DAW bar 1 beat 1 = 0). Notes with a gap of more than CALL_PHRASE_GAP
## beats between them are separate calls. Each call is answered in the same rhythm,
## 1 bar + answer_delay beats later; a call longer than that is answered whole bars
## later still, so a call and its answer never overlap.
func _call_chart() -> Array:
	var notes := _read_midi_notes(CALL_MIDI)
	var phrases := []
	for n in notes:
		if phrases.is_empty() or n[0] - phrases[-1][-1][0] > CALL_PHRASE_GAP:
			phrases.append([])
		phrases[-1].append(n)
	var out := []
	for ph in phrases:
		var written := _written_response(ph)
		if written >= 0.0:
			# I wrote the response myself: the first half is the call, the second half
			# its copy. Each ball is answered by that copy's (median) delay.
			for i in ph.size() / 2:
				var n: Array = ph[i]
				out.append({"beat": n[0], "kind": "fire" if n[1] < CALL_FIRE_BELOW else "ice", "hit": n[0] + written})
			continue
		var shift := 4.0 + answer_delay
		while ph[0][0] + shift <= ph[-1][0] + 0.01:   # still calling: wait another bar
			shift += 4.0
		for n in ph:
			out.append({"beat": n[0], "kind": "fire" if n[1] < CALL_FIRE_BELOW else "ice", "hit": n[0] + shift})
	return out


## A phrase whose second half repeats its first half (same fire/ice order, each note
## moved by about the same amount, starting after the call ends) has its response
## written in the MIDI. Returns that delay in beats, or -1 if it's a call on its own.
func _written_response(ph: Array) -> float:
	if ph.size() < 2 or ph.size() % 2 != 0:
		return -1.0
	var half := ph.size() / 2
	if ph[half][0] <= ph[half - 1][0]:
		return -1.0
	var shifts := []
	for i in half:
		if (ph[i][1] < CALL_FIRE_BELOW) != (ph[half + i][1] < CALL_FIRE_BELOW):
			return -1.0
		shifts.append(ph[half + i][0] - ph[i][0])
	shifts.sort()
	if shifts[-1] - shifts[0] > 0.25:
		return -1.0
	return (shifts[(half - 1) / 2] + shifts[half / 2]) / 2.0


## Note-on events of a .mid file as [[beat, key], ...], sorted by time.
static func _read_midi_notes(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var d := f.get_buffer(f.get_length())
	if d.size() < 14 or d.slice(0, 4).get_string_from_ascii() != "MThd":
		return []
	var ntracks: int = (d[10] << 8) | d[11]
	var div: int = (d[12] << 8) | d[13]
	var pos := [8 + ((d[4] << 24) | (d[5] << 16) | (d[6] << 8) | d[7])]
	var out := []
	for _tr in ntracks:
		var i: int = pos[0]
		if i + 8 > d.size():
			break
		var end: int = i + 8 + ((d[i + 4] << 24) | (d[i + 5] << 16) | (d[i + 6] << 8) | d[i + 7])
		pos[0] = i + 8
		var t := 0
		var run := 0
		while pos[0] < end:
			t += _vlq(d, pos)
			var st: int = d[pos[0]]
			if st == 0xFF:                  # meta event
				pos[0] += 2
				pos[0] += _vlq(d, pos)
				continue
			if st == 0xF0 or st == 0xF7:    # sysex
				pos[0] += 1
				pos[0] += _vlq(d, pos)
				continue
			if (st & 0x80) != 0:
				run = st
				pos[0] += 1
			var ty := run & 0xF0
			if ty == 0x90:
				if d[pos[0] + 1] > 0:
					out.append([float(t) / div, d[pos[0]]])
				pos[0] += 2
			elif ty == 0xC0 or ty == 0xD0:
				pos[0] += 1
			else:
				pos[0] += 2
		pos[0] = end
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


static func _vlq(d: PackedByteArray, pos: Array) -> int:
	var v := 0
	while true:
		var b: int = d[pos[0]]
		pos[0] += 1
		v = (v << 7) | (b & 0x7F)
		if (b & 0x80) == 0:
			return v
	return v


## As many PATTERNS as the song has room for (each takes _pattern_bars bars; the
## last one only needs its call + answer bar before the song ends).
func _patterns_that_fit() -> Array:
	var room := mini(_room(), _patterns.size())
	if room == _patterns.size():
		return _patterns
	var picked := []
	for i in room:
		picked.append(_patterns[roundi(i * (_patterns.size() - 1) / maxf(room - 1, 1.0))])
	return picked


## How many patterns the song has room for.
func _room() -> int:
	var bars := int((_song_stream.get_length() - Conductor.first_beat_offset) / (4.0 * Conductor.seconds_per_beat) + 0.05)
	return maxi((bars - _first_call_bar - 2) / _pattern_bars + 1, 1)


# --- record mode -------------------------------------------------------------------
## F2: the song plays with nothing flying. In each CALL bar, tap what the tower
## should throw: A = an ice ball, D = a fire ball. Taps snap to record_snap.
## Z undoes the last tap. When the song ends (or Enter), the patterns are saved
## into the PATTERNS list at the top of this script and SPACE plays them.
## A call bar you don't tap keeps the pattern it had.
func _start_record() -> void:
	Conductor.stop()
	audio.stream = _song_stream
	audio.volume_db = 0.0
	_balls.clear()
	_spells.clear()
	_pops.clear()
	_hurt = {}
	_rec = []
	for i in _room():
		_rec.append([])
	_rec_undo = []
	_rec_msg = ""
	_phase = Phase.RECORD
	Conductor.play()


func _rec_tap(kind: String) -> void:
	var raw := (Conductor.live_position() - Conductor.input_offset - Conductor.first_beat_offset) / Conductor.seconds_per_beat
	var beat := raw
	if record_snap > 0:
		beat = roundf(raw * record_snap) / record_snap
	var last_slot := 4.0 - (1.0 / record_snap if record_snap > 0 else 0.05)   # last grid spot in a bar
	var rel := beat / 4.0 - _first_call_bar        # bars since the first call
	var idx := floori(rel / _pattern_bars + 0.0001)
	var b := snappedf(maxf(rel - idx * _pattern_bars, 0.0) * 4.0, 0.001)   # beat within that bar
	if b >= 3.999:
		# Just past the end of the call bar: a late tap meant for the end of the bar.
		# Within REC_END_LEEWAY beats it sticks to the bar's last spot instead of being lost.
		var past := raw - ((_first_call_bar + idx * _pattern_bars) * 4 + 4.0)
		if past < REC_END_LEEWAY:
			b = last_slot
	if idx < 0 or idx >= _rec.size() or b >= 3.999:
		_play(kind, -2.0 if kind == "fire" else -8.0)
		_rec_note("Tap during a CALL bar")
		return
	var pat: Array = _rec[idx]
	var launch_beat: float = (_first_call_bar + idx * _pattern_bars) * 4 + b
	for i in range(pat.size() - 1, -1, -1):
		if absf(pat[i][0] - b) < 0.01:             # same beat again: replace it
			pat.remove_at(i)
			_rec_undo = _rec_undo.filter(func(u): return not (u[0] == idx and absf(u[1] - b) < 0.01))
			_drop_rec_ball(launch_beat)
	pat.append([b, kind])
	pat.sort_custom(func(x, y): return x[0] < y[0])
	_rec_undo.append([idx, b])
	# The ball really flies, and one bar later the wand answers it by itself,
	# so you hear the whole call and response while you record.
	# The throw sound: if the tap came a little before its beat, it waits and plays
	# right on the beat (like in the game); otherwise it plays at once.
	var launch_t := Conductor.time_of_beat(launch_beat)
	var on_grid := Conductor.song_position < launch_t - AudioServer.get_output_latency()
	if not on_grid:
		_play(kind, -2.0 if kind == "fire" else -8.0)
	var hit_t := Conductor.time_of_beat(launch_beat + TRAVEL_BEATS)
	_balls.append({"kind": kind, "launch_t": launch_t,
		"hit_t": hit_t, "arrive_v": hit_t + Conductor.input_offset, "beat": launch_beat,
		"lane": b, "state": "fly", "launched": not on_grid, "impact": -1.0, "burst_sfx": null, "hurt": false})


func _drop_rec_ball(launch_beat: float) -> void:
	_balls = _balls.filter(func(ball): return not (ball["state"] == "fly" and absf(ball.get("beat", -99.0) - launch_beat) < 0.01))


func _rec_undo_last() -> void:
	if _rec_undo.is_empty():
		return
	var last: Array = _rec_undo.pop_back()
	var idx: int = last[0]
	var pat: Array = _rec[idx]
	for i in pat.size():
		if absf(pat[i][0] - last[1]) < 0.01:
			pat.remove_at(i)
			break
	_drop_rec_ball((_first_call_bar + idx * _pattern_bars) * 4 + last[1])
	_rec_note("Undone")


func _rec_note(t: String) -> void:
	_rec_msg = t
	_rec_msg_t = Time.get_ticks_msec() / 1000.0


func _save_record() -> void:
	Conductor.stop()
	var base := _patterns_that_fit()
	var out := []
	for i in _rec.size():
		if not _rec[i].is_empty():
			out.append(_rec[i])
		elif i < base.size():
			out.append(base[i])
	_patterns = out
	use_call_midi = false              # play what you just recorded, not the Call MIDI
	_phase = Phase.CARD
	if _write_patterns(out):
		_rec_note("Saved into wizard_game.gd!  SPACE to play them")
	else:
		_rec_note("Couldn't write the file -- patterns printed in Output")
	print("const PATTERNS := [\n" + _patterns_text(out) + "]")


func _patterns_text(pats: Array) -> String:
	var lines := ""
	for p in pats:
		var notes := []
		for n in p:
			var x: float = n[0]
			var num := str(int(x)) if is_equal_approx(x, roundf(x)) else String.num(x, 3)
			notes.append('[%s, "%s"]' % [num, n[1]])
		lines += "\t[" + ", ".join(notes) + "],\n"
	return lines


## Rewrites the PATTERNS list in this script's source (only works when run from the editor).
func _write_patterns(pats: Array) -> bool:
	var path: String = get_script().resource_path
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var src := f.get_as_text()
	f.close()
	var head := "const PATTERNS := [\n"
	var a := src.find(head)
	var b := src.find("\n]\n", a)
	if a < 0 or b < 0:
		return false
	src = src.substr(0, a) + head + _patterns_text(pats) + src.substr(b + 1)
	f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(src)
	f.close()
	return true


func _on_song_finished() -> void:
	if _phase == Phase.RECORD:
		_save_record()
	elif _phase == Phase.PLAY:
		_phase = Phase.DONE
	elif _phase == Phase.DEMO:           # the practice metronome ran out: start it again
		_phase = Phase.CARD
		_start_demo(_demo_step)


## SPACE on a computer, the Skip button on a phone.
func _skip_practice() -> void:
	if _phase == Phase.DEMO:
		_start()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ESCAPE:
				if _phase == Phase.DONE:    # results screen: straight to the menu
					get_tree().change_scene_to_file("res://MainMenu.tscn")
				else:
					_pause.open()
				get_viewport().set_input_as_handled()
			KEY_F2:
				if _phase == Phase.RECORD:
					_save_record()
				else:
					_start_record()
			KEY_R:
				if _phase == Phase.RECORD:
					_start_record()
				else:
					_start()
			KEY_Z:
				if _phase == Phase.RECORD:
					_rec_undo_last()
			KEY_SPACE, KEY_ENTER:
				if _phase == Phase.RECORD:
					if e.keycode == KEY_ENTER:
						_save_record()
				elif _phase != Phase.PLAY:
					_start()
			KEY_A, KEY_LEFT:
				if _phase == Phase.RECORD:
					_rec_tap("ice")
				else:
					_cast("ice")
			KEY_D, KEY_RIGHT:
				if _phase == Phase.RECORD:
					_rec_tap("fire")
				else:
					_cast("fire")
	elif e is InputEventMouseButton and e.pressed and _phase == Phase.RECORD:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_rec_tap("ice")
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			_rec_tap("fire")
	elif e is InputEventMouseButton and e.pressed:
		# a tap / click: left half of the screen = ICE, right half = FIRE (phones too:
		# touches arrive as left clicks). Right click is FIRE anywhere.
		if _phase == Phase.CARD or _phase == Phase.DONE:
			if e.button_index == MOUSE_BUTTON_LEFT:
				_start()
			return
		if e.button_index == MOUSE_BUTTON_LEFT:
			_cast("ice" if _tap_side(e) == "left" else "fire")
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			_cast("fire")


func _tap_side(e: InputEventMouseButton) -> String:
	return "left" if e.position.x < get_viewport().get_visible_rect().size.x * 0.5 else "right"


## A spell fires every press. If a ball is inside the hit window, the spell
## flies to the burst point and lands exactly when the ball gets there.
func _cast(kind: String, auto := false) -> void:
	if not (_phase == Phase.PLAY or _phase == Phase.DEMO or (_phase == Phase.RECORD and auto)):
		return
	if _frozen and not _cast_frozen(kind):
		return
	var now := Conductor.live_position()
	var v := now + Conductor.video_offset
	_cast_v = v
	if not auto and not _last_cast.is_empty() and kind != _last_cast["kind"] and now - _last_cast["t"] < BOTH_AT_ONCE:
		_undo_both(_last_cast)       # mashing both spells: the hit is cancelled
		_last_cast = {}
		_play("cast_" + kind, -4.0)
		return
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
	var grade := ""
	if best < 0:
		_play("cast_" + kind, -4.0)
		if not auto:
			_wreck_early(now)          # pressed too early for the next ball: it gets through
	else:
		var b: Dictionary = _balls[best]
		if b["kind"] == kind:          # same element just feeds it -- it gets through
			b["state"] = "wrong"
			_cut_burst(b)
			_miss()
			_play("cast_" + kind, -4.0)
		else:
			grade = "Perfect" if absf(best_err) <= PERFECT else "Good"
			b["state"] = "target"
			spell["impact"] = maxf(v + 0.05, b["arrive_v"])
			b["impact"] = spell["impact"]
			_tally[grade] += 1
			_pops.append({"text": grade + "!" if grade == "Perfect" else grade,
				"col": COL[kind], "t0": spell["impact"]})
	_spells.append(spell)
	if not auto:
		_last_cast = {"kind": kind, "t": now, "ball": best if grade != "" else -1, "grade": grade, "spell": spell}


## A press with no ball in reach while one is just about to arrive (within EARLY):
## that's spamming, so the ball gets through. Balls that wait for you in practice are spared.
func _wreck_early(now: float) -> void:
	for b in _balls:
		if b["state"] != "fly" or b.get("hold", false):
			continue
		var ahead: float = b["hit_t"] - (now - Conductor.input_offset)
		if ahead > GOOD and ahead <= EARLY:
			b["state"] = "wrong"
			_cut_burst(b)
			_miss()
			return


## Both spells at once: take back the hit the first press made.
func _undo_both(last: Dictionary) -> void:
	last["spell"]["impact"] = -1.0
	if last["ball"] < 0 or last["ball"] >= _balls.size():
		return
	var b: Dictionary = _balls[last["ball"]]
	if b["state"] != "target":
		return
	b["state"] = "wrong"
	_cut_burst(b)
	_tally[last["grade"]] -= 1
	_miss()
	_pops = _pops.filter(func(p): return p["t0"] != b["impact"])


## Practice, 3rd try: the ball hangs at the burst point until you press. The right
## element blasts it (and time runs again); the wrong one just fizzles.
func _freeze_ball() -> void:
	_frozen = true
	_freeze_v = Conductor.visual_position


func _unfreeze() -> void:
	_frozen = false


## While frozen the metronome keeps going; the ball's clock is pushed along with
## it every frame, so it stays right at the burst point.
func _hold_frozen_ball() -> void:
	var v := Conductor.visual_position
	var dt := v - _freeze_v
	_freeze_v = v
	var b: Dictionary = _balls[0]
	b["launch_t"] += dt
	b["hit_t"] += dt
	b["arrive_v"] += dt
	_demo_end = b["hit_t"] + 1.4


## Wrong element: it just fizzles and the ball keeps waiting. The right one is a
## normal (on-time) cast at the waiting ball.
func _cast_frozen(kind: String) -> bool:
	if _balls[0]["kind"] == kind:
		_cast_v = Conductor.visual_position
		_play("cast_" + kind, -4.0)
		return false
	_unfreeze()
	_balls[0]["hold"] = false
	return true


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
	if _skip_btn:
		_skip_btn.visible = _phase == Phase.DEMO
	if _frozen:
		_hold_frozen_ball()
	elif _phase == Phase.DEMO and not _balls.is_empty() and _balls[0].get("hold", false) and _balls[0]["state"] == "fly" and Conductor.visual_position >= _balls[0]["arrive_v"]:
		_freeze_ball()
	if _phase == Phase.RECORD and Conductor.playing:
		# record mode casts the opposite element by itself, exactly when a perfect press registers
		for b in _balls:
			if b["state"] == "fly" and Conductor.live_position() >= b["hit_t"] + Conductor.input_offset:
				_cast("ice" if b["kind"] == "fire" else "fire", true)
	if _phase == Phase.DEMO and Conductor.playing and Conductor.song_position >= _demo_end:
		var got: bool = not _balls.is_empty() and _balls[0]["state"] == "target"
		if not got:
			_start_demo(_demo_step, true)    # missed: same shot again
		elif _demo_step == 0:
			_start_demo(1)                   # now the other element
		else:
			_start()                         # both done: straight into the song, no "tap to start"
	if (_phase == Phase.PLAY or _phase == Phase.DEMO or _phase == Phase.RECORD) and Conductor.playing:
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
			if b["burst_sfx"] == null and b["state"] in ["fly", "target"] and pos >= b["hit_t"] - lat 					and not (b.get("hold", false) and b["state"] == "fly"):
				b["burst_sfx"] = _play("burst_" + ("ice" if b["kind"] == "fire" else "fire"), -2.0)
			if b["state"] == "fly" and pos - Conductor.input_offset > b["hit_t"] + GOOD + MISS_TAIL and not b.get("hold", false):
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
	if _phase == Phase.PLAY or _phase == Phase.DEMO or _phase == Phase.RECORD:
		beat_pulse = exp(-fposmod(Conductor.song_position_in_beats, 1.0) * 5.0)
	_draw_backdrop(beat_pulse)
	_draw_enemy(v)
	if _phase == Phase.RECORD:
		_draw_record()             # under the balls, so you can watch them fly
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
	if _phase != Phase.RECORD:
		_draw_hud()
	if _phase == Phase.DEMO:
		# on the dark ground, clear of the ball's flight and the burst in the sky
		# the same caption box, in the same spot, as every level (TutorialUI)
		var head := "Try again!" if _demo_retry else ("Practice  1/2" if _demo_step == 0 else "Practice  2/2")
		var touch := TutorialUI.is_touch()
		if _demo_step == 0:
			TutorialUI.caption(self, head, "Fireball? Tap the LEFT side!" if touch else "Fireball? Press A for ICE!",
				COL["ice"].darkened(0.25))
		else:
			TutorialUI.caption(self, head, "Iceball? Tap the RIGHT side!" if touch else "Iceball? Press D for FIRE!",
				COL["fire"].darkened(0.2))
		_draw_key_prompt(v)
		TutorialUI.skip_hint(self, "SPACE: skip", Color(1, 1, 1, 0.55))   # light on the dark ground
	elif _phase == Phase.CARD:
		_draw_card()
		if Time.get_ticks_msec() / 1000.0 - _rec_msg_t < 6.0:
			_text(_rec_msg, Vector2(576, 530), 22, Color.WHITE, true, 1.0)
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
	# recoil after a cast; a cast from before the clock restarted (practice -> game) doesn't count
	var since := v - _cast_v
	var kick := Vector2(-12, 12) * (clampf(1.0 - since / 0.16, 0.0, 1.0) if since >= 0.0 else 0.0)
	if _phase == Phase.PLAY:
		kick += _walk_in(v)
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


## When the game starts the gnome walks up from the bottom left to his spot,
## wand in hand: eases in over WALK_IN seconds, bobbing with each step.
func _walk_in(v: float) -> Vector2:
	var k := clampf(v / WALK_IN, 0.0, 1.0)
	if k >= 1.0:
		return Vector2.ZERO
	var left := 1.0 - k
	var ease := left * left                         # ease-out: on screen at once, slowing as he arrives
	var bob := -absf(sin(v * PI * 2.0)) * 14.0 * minf(left * 4.0, 1.0)
	return WALK_FROM * ease + Vector2(0, bob)


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
	# a phone taps the screen halves; a computer presses A / D. The two labels
	# mirror each other (clear of the skip hint in the corner).
	var touch := TutorialUI.is_touch()
	_text("tap left: ICE" if touch else "A: ICE", Vector2(380, VP.y - 22), 18, COL["ice"], true)
	_text("tap right: FIRE" if touch else "D: FIRE", Vector2(VP.x - 380, VP.y - 22), 18, COL["fire"], true)


## Record mode: one row per pattern (its call bar), with the taps on a 4-beat strip.
func _draw_record() -> void:
	var beats := Conductor.song_position_in_beats
	var bar := floori(beats / 4.0)
	var rel := bar - _first_call_bar
	var cur := floori(float(rel) / _pattern_bars)
	var in_call := rel >= 0 and rel % _pattern_bars == 0 and cur < _rec.size()
	var x0 := 330.0
	var w := 480.0
	var y0 := 70.0
	var row_h := 30.0
	var r := Rect2(x0 - 130, y0 - 46, w + 250, 62 + row_h * _rec.size())
	draw_rect(r.grow(4), Color(INK, 0.6))
	draw_rect(r, Color(1, 0.97, 0.88, 0.72))
	_text("RECORD", Vector2(x0 - 110, y0 - 16), 22, Color(0.8, 0.1, 0.1))
	var status := "listen..."
	if in_call:
		status = "CALL - tap now!"
	elif rel + 1 >= 0 and (rel + 1) % _pattern_bars == 0 and (rel + 1) / _pattern_bars < _rec.size():
		status = "get ready..."
	_text("DAW bar %d   %s" % [maxi(bar + 1, 1), status], Vector2(x0, y0 - 16), 22, INK)
	for i in _rec.size():
		var y := y0 + 8 + row_h * i
		var live := in_call and i == cur
		draw_rect(Rect2(x0, y, w, row_h - 8), Color(1, 0.85, 0.4) if live else Color(0.9, 0.86, 0.76))
		for k in 5:
			draw_line(Vector2(x0 + w * k / 4.0, y), Vector2(x0 + w * k / 4.0, y + row_h - 8), Color(INK, 0.5), 2.0 if k % 4 == 0 else 1.0)
		_text("bar %d" % (_first_call_bar + i * _pattern_bars + 1), Vector2(x0 - 110, y + 17), 16, INK)
		for n in _rec[i]:
			draw_circle(Vector2(x0 + w * float(n[0]) / 4.0, y + (row_h - 8) / 2.0), 9.0, COL[n[1]])
		if _rec[i].is_empty():
			_text("(keeps old)", Vector2(x0 + w + 10, y + 17), 14, INK.lightened(0.4))
		if live:
			var px := x0 + w * fposmod(beats, 4.0) / 4.0
			draw_line(Vector2(px, y - 3), Vector2(px, y + row_h - 5), Color(0.8, 0.1, 0.1), 2.0)
	if Time.get_ticks_msec() / 1000.0 - _rec_msg_t < 1.5:
		_text(_rec_msg, Vector2(576, 500), 24, Color.WHITE, true, 1.0)
	_text("A = throw ICE    D = throw FIRE    Z undo    R start over    Enter save", Vector2(576, VP.y - 22), 18, Color(1, 1, 1, 0.85), true)


## Practice: the press box (A / D on a computer, TAP on a phone) with a box closing in on it that wraps it exactly
## when the ball arrives (press then). While the ball waits, the square pulses.
## Same box, same height as every level (TutorialUI), but it sits over the half of
## the screen you tap: left for ICE, right for FIRE (the right one lines up with
## the other levels' TAP box).
func _draw_key_prompt(v: float) -> void:
	if _balls.is_empty():
		return
	var b: Dictionary = _balls[0]
	var col: Color = COL["ice"] if _demo_step == 0 else COL["fire"]
	var c := TutorialUI.tap_at
	if _demo_step == 0:
		c.x = VP.x - c.x               # the mirror spot on the left half
	var live: bool = b["state"] == "fly"
	var key := "A" if _demo_step == 0 else "D"     # on a phone: TAP
	TutorialUI.tap_box(self, live, c, col, key)
	if live:
		TutorialUI.square(self, b["arrive_v"] - v, _frozen, GOOD, c, col, key)


func _draw_card() -> void:
	_panel(Rect2(376, 190, 400, 150))
	_text("WIZARD TOWER", Vector2(576, 250), 40, INK, true)
	_text("Tap to start", Vector2(576, 300), 22, INK.lightened(0.3), true)


func _draw_results() -> void:
	_panel(Rect2(326, 150, 500, 320))
	_text("TOWER DEFENDED!" if _tally["Miss"] <= 6 else "THE TOWER IS SCORCHED", Vector2(576, 210), 32, INK, true)
	var got: int = _tally["Perfect"] + _tally["Good"]
	_results.draw_percent(self, _font, Vector2(576, 320), got, got + _tally["Miss"])
	_text(_results.hint(), Vector2(576, 440), 18, INK.lightened(0.4), true)


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


## Your sound files, in res://audio/sfx/wizard/ (see the README there):
## sound key -> file name (any of .wav / .ogg / .mp3). A missing file keeps the
## synth stand-in, so you can replace them one at a time.
const SFX_DIR := "res://audio/sfx/wizard/"
const SFX_FILES := {
	"fire": "launch_fire", "ice": "launch_ice", "hurt": "hurt",
	"cast_fire": "cast_fire", "cast_ice": "cast_ice",
	"burst_fire": "burst_fire", "burst_ice": "burst_ice",
}

func _load_sfx_files() -> void:
	for key in SFX_FILES:
		for ext in ["wav", "ogg", "mp3"]:
			var path: String = SFX_DIR + SFX_FILES[key] + "." + ext
			if ResourceLoader.exists(path):
				_sfx[key] = load(path)
				break


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
