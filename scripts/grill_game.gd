extends Node2D
## "Grill Master" minigame. Call and response: the blue EXAMPLE tongs (right)
## play a bar -- a tong clack-clack, a 3-part flip, or the final pop -- and the
## player's tongs (left) answer it on the next bar with SPACE, in the same rhythm.
## Only the answers are graded.
##
## Starts with a practice round over a metronome: first the tong claps, then the
## flip, each needing `practice_goal` clean answer bars. S skips it.
##
## Chart: beatmaps/grill.tres -- cues { beat, cue: "tap" | "flip" | "pop",
## role: "call" | "answer" }. Flip and pop bars are 3 presses on beats 1-2-3.
##   Space / click  answer     S  skip practice     R  restart     Esc  menu

enum Phase { PRACTICE, TRANSITION, SONG }

const PERFECT := 0.075
const GOOD := 0.15
const MISS_TAIL := 0.03            ## seconds past the late edge of GOOD before it's a Miss
const VP := Vector2(1152, 648)
const INK := Color(0.2, 0.14, 0.12)
## Beats within a bar for each move (flip / pop: beats 1-2-3).
const PATTERN := {"tap": [2.5, 3.0], "flip": [0.0, 1.0, 2.0], "pop": [0.0, 1.0, 2.0]}
const SFX := {"tong": "res://audio/sfx/grill/tong.wav", "flip": "res://audio/sfx/grill/flip.wav",
	"scrape": "res://audio/sfx/grill/scrape.wav", "sizzle": "res://audio/sfx/grill/sizzle.wav",
	"pop": "res://audio/sfx/grill/pop.wav"}
## The flip animation is driven by the music clock, pinned to the bar: grab on
## beat 1 (the hit), top of the toss on beat 2 (the scrape), landing on beat 3
## (the sizzle), then back to rest. Values are frames of the "flip" animation.
const FLIP_GRAB := 7
const FLIP_TOP := 12
const FLIP_LAND := 19
const FLIP_END := 27
const FLIP_REACH := 0.5            ## beats the example tongs start reaching before beat 1
const FLIP_RETURN := 0.5           ## beats to go back to rest after the landing

@export var beatmap: Beatmap

@export_group("Layout")
@export var patty_pos := Vector2(605, 300)          ## your patty -- steam rises from here
@export var example_patty_pos := Vector2(730, 290)  ## the example tongs' patty
@export var bun_pos := Vector2(320, 520)            ## your bun (the pop lands here)
@export var example_bun_pos := Vector2(1020, 520)   ## the example tongs' bun
@export var you_pos := Vector2(318, 250)            ## tip of the practice "YOU" arrow

@export_group("Practice round")
@export var practice: bool = true
## Clean answer bars needed in each practice step (claps, then flip).
@export var practice_goal: int = 2
@export var practice_metronome_db: float = -8.0
@export var practice_outro: float = 2.0

@onready var audio: AudioStreamPlayer = $AudioStreamPlayer
@onready var tongs: AnimatedSprite2D = $Stage/Tongs
@onready var example: AnimatedSprite2D = $Stage/ExampleTongs

var _phase := Phase.SONG
var _practice_passed := false
var _song_stream: AudioStream
var _metronome: AudioStreamWAV

var _calls: Array = []             ## { beat, time, cue, part, sounded, shown } -- example tongs
var _answers: Array = []           ## { beat, time, cue, part, bar } -- still to grade, in order
var _bars := {}                    ## bar id -> { left: int, missed: bool } (practice success)
var _next_cycle := 4.0             ## practice: beat the next call bar starts
var _step := 0                     ## practice: 0 = tong claps, 1 = flip
var _step_ok := 0                  ## practice: clean answer bars in this step
var banner := ""

var score := 0
var combo := 0
var best_combo := 0
var _tally := {"Perfect": 0, "Good": 0, "Miss": 0}
var _fx: Array = []                ## { kind, t0, pos } -- steam, pop, miss puff
var _landed := false               ## your patty is on your bun
var _example_landed := false
var _finished := false

var _flips := {}                   ## AnimatedSprite2D -> song time of beat 1 of the flip it's doing
var _fx_layer: Node2D
var _sfx: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _panel_sb: StyleBoxFlat


func _ready() -> void:
	_fx_layer = Node2D.new()          # effects + HUD above the grill art
	add_child(_fx_layer)
	_fx_layer.draw.connect(_draw_fx)
	for k in SFX:
		if ResourceLoader.exists(SFX[k]):
			_sfx[k] = load(SFX[k])
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_panel_sb = StyleBoxFlat.new()
	_panel_sb.bg_color = Color(1, 0.97, 0.88)
	_panel_sb.set_corner_radius_all(18)
	_panel_sb.set_border_width_all(4)
	_panel_sb.border_color = INK

	_song_stream = audio.stream
	Conductor.stream_player = audio
	if beatmap:
		Conductor.bpm = beatmap.bpm
		Conductor.first_beat_offset = beatmap.first_beat_offset
		Conductor.video_offset = beatmap.video_offset
		Conductor.input_offset = Settings.input_offset(beatmap.input_offset)
	Conductor.song_finished.connect(_on_song_finished)
	_restart()


## Conductor is an autoload and outlives this scene -- stop it before our
## AudioStreamPlayer is freed, or its _process would poke a dead node.
func _exit_tree() -> void:
	Conductor.song_finished.disconnect(_on_song_finished)
	Conductor.stop()
	Conductor.stream_player = null


func _restart() -> void:
	if practice and not _practice_passed:
		_start_practice()
	else:
		_start_song()


func _reset_round() -> void:
	_calls.clear()
	_answers.clear()
	_bars.clear()
	_fx.clear()
	_landed = false
	_example_landed = false
	_finished = false
	banner = ""
	score = 0
	combo = 0
	best_combo = 0
	_tally = {"Perfect": 0, "Good": 0, "Miss": 0}
	_flips.clear()
	for t in [tongs, example]:
		t.play(&"flip")
		t.stop()
		t.frame = 0


func _start_practice() -> void:
	_phase = Phase.PRACTICE
	_step = 0
	_step_ok = 0
	_reset_round()
	_next_cycle = 4.0            # one bar of clicks first
	if _metronome == null:
		_metronome = ClickTrack.make(Conductor.bpm, 64, Conductor.beats_per_measure, Conductor.first_beat_offset)
	audio.stream = _metronome
	audio.volume_db = practice_metronome_db
	Conductor.play()


func _start_song() -> void:
	_phase = Phase.SONG
	_reset_round()
	audio.stream = _song_stream
	audio.volume_db = 0.0
	for c in (beatmap.compiled(Conductor) if beatmap else []):
		var cue := {"beat": c["beat"], "time": c["time"], "cue": c["cue"],
			"part": _part(c["cue"], c["beat"]), "bar": int(floor(c["beat"] / 4.0))}
		if c.get("role", "answer") == "call":
			cue["sounded"] = true      # the song itself plays the example
			cue["shown"] = false
			_calls.append(cue)
		else:
			_answers.append(cue)
	Conductor.play()


## Which press of its bar a cue is (0-based), from the bar's pattern.
func _part(cue: String, beat: float) -> int:
	return maxi(0, (PATTERN.get(cue, [0.0]) as Array).find(fposmod(beat, 4.0)))


func _on_song_finished() -> void:
	if _phase == Phase.PRACTICE:
		# keep practising: the click track starts over, and so do the bars
		_calls.clear()
		_answers.clear()
		_bars.clear()
		_next_cycle = 4.0
		Conductor.play()
	elif _phase == Phase.SONG:
		_finished = true


# --- practice ------------------------------------------------------------------

## Queue the next call bar + answer bar half a beat before it starts -- late enough
## that the previous answer bar has been judged (so a passed step switches in time).
func _schedule_practice() -> void:
	if _phase != Phase.PRACTICE or Conductor.song_position_in_beats < _next_cycle - 0.5:
		return
	var cue: String = ["tap", "flip"][_step]
	var bar := int(_next_cycle / 4.0)
	for off in PATTERN[cue]:
		var cb: float = _next_cycle + off
		var ab: float = _next_cycle + 4.0 + off
		_calls.append({"beat": cb, "time": Conductor.time_of_beat(cb), "cue": cue,
			"part": _part(cue, cb), "sounded": false, "shown": false})
		_answers.append({"beat": ab, "time": Conductor.time_of_beat(ab), "cue": cue,
			"part": _part(cue, ab), "bar": bar + 1})
	_bars[bar + 1] = {"left": (PATTERN[cue] as Array).size(), "missed": false}
	_next_cycle += 8.0


## A practice answer bar is done -- count it if nothing in it was missed.
func _bar_result(bar: int, missed: bool) -> void:
	if _phase != Phase.PRACTICE or not _bars.has(bar):
		return
	var b: Dictionary = _bars[bar]
	b["left"] -= 1
	b["missed"] = b["missed"] or missed
	if b["left"] > 0:
		return
	_bars.erase(bar)
	if b["missed"]:
		return
	_step_ok += 1
	if _step_ok < practice_goal:
		return
	if _step == 0:
		_step = 1                  # claps done -- on to the flip (from the next cycle)
		_step_ok = 0
		return
	# both steps passed: finish, cheer, then the real song from the top
	_phase = Phase.TRANSITION
	_practice_passed = true
	_calls = _calls.filter(func(c): return c["time"] <= Conductor.song_position)
	_answers.clear()
	banner = "Nice! Here we go!"
	await get_tree().create_timer(practice_outro).timeout
	if _phase == Phase.TRANSITION:   # not interrupted by R / S / Esc
		_start_song()


# --- per frame -------------------------------------------------------------------

func _process(_dt: float) -> void:
	var now: float = Conductor.song_position
	var vis: float = Conductor.visual_position
	var latency := AudioServer.get_output_latency()
	_schedule_practice()

	for c in _calls:
		# the example tongs start reaching for the patty just before a flip's beat 1
		if c["cue"] != "tap" and c["part"] == 0 and not c.get("reached", false) \
				and vis >= c["time"] - FLIP_REACH * Conductor.seconds_per_beat:
			c["reached"] = true
			_flips[example] = c["time"]
		# practice: the example's sound, fired output-latency early so it's heard on the beat
		if not c["sounded"] and now >= c["time"] - latency:
			c["sounded"] = true
			_sound(c["cue"], c["part"])
		if not c["shown"] and vis >= c["time"]:
			c["shown"] = true
			_act(example, c["cue"], c["part"], c["beat"], true)
	_calls = _calls.filter(func(c): return not (c["sounded"] and c["shown"]))
	_drive_flips(vis)

	# an answer nobody pressed for -> Miss
	while not _answers.is_empty() and now > _answers[0]["time"] + Conductor.input_offset + GOOD + MISS_TAIL:
		var a: Dictionary = _answers.pop_front()
		_grade(a, "Miss")
	_fx = _fx.filter(func(f): return now - f["t0"] < 1.2)
	_fx_layer.queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	var pressed: bool = (e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_SPACE) \
		or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
	if pressed:
		_press()
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_S:
				if _phase == Phase.PRACTICE or _phase == Phase.TRANSITION:
					_practice_passed = true
					_start_song()
			KEY_R:
				_restart()
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://MainMenu.tscn")


func _press() -> void:
	if _finished:
		return
	if not _answers.is_empty():
		var c: Dictionary = _answers[0]
		var err: float = Conductor.timing_error(c["beat"])
		if absf(err) <= GOOD:
			_answers.pop_front()
			_grade(c, "Perfect" if absf(err) <= PERFECT else "Good")
			return
	if not _flips.has(tongs):
		_play(tongs, &"tap")   # nothing to answer -- just clack the tongs (unless mid-flip)
	if _phase != Phase.SONG:
		_sound("tap", 0)


func _grade(c: Dictionary, grade: String) -> void:
	_bar_result(c.get("bar", -1), grade == "Miss")
	if _phase != Phase.SONG:
		if grade != "Miss":
			_sound(c["cue"], c["part"])   # practice has no song to play the answer
			_act(tongs, c["cue"], c["part"], c["beat"], false)
		else:
			_fx.append({"kind": "miss", "t0": Conductor.song_position, "pos": patty_pos})
		return
	_tally[grade] += 1
	if grade == "Miss":
		combo = 0
		_fx.append({"kind": "miss", "t0": Conductor.song_position, "pos": patty_pos})
		return
	combo += 1
	best_combo = maxi(best_combo, combo)
	score += 100 if grade == "Perfect" else 50
	_act(tongs, c["cue"], c["part"], c["beat"], false)


## Animate one press of a move on a set of tongs.
func _act(who: AnimatedSprite2D, cue: String, part: int, beat: float, is_example: bool) -> void:
	var t := Conductor.song_position
	match cue:
		"tap":
			_play(who, &"tap")
		"flip", "pop":
			# any press of the bar starts (or keeps) the flip, pinned to that bar's beat 1
			var beat1 := Conductor.time_of_beat(beat - float(part))
			if not is_equal_approx(_flips.get(who, -1.0), beat1):
				_flips[who] = beat1
			if part != 2:
				return
			if cue == "pop":                            # beat 3 of the pop bar: onto the bun
				if is_example:
					_example_landed = true
				else:
					_landed = true
				_fx.append({"kind": "pop", "t0": t, "pos": example_bun_pos if is_example else bun_pos})
			else:                                       # beat 3: lands with a sizzle
				_fx.append({"kind": "steam", "t0": t, "pos": example_patty_pos if is_example else patty_pos})


func _play(who: AnimatedSprite2D, anim: StringName) -> void:
	_flips.erase(who)
	who.stop()
	who.play(anim)


## Set each flipping tongs' frame from the music clock (see FLIP_GRAB etc.).
func _drive_flips(vis: float) -> void:
	for who: AnimatedSprite2D in _flips.keys():
		var b: float = (vis - _flips[who]) / Conductor.seconds_per_beat   # beats since beat 1
		var f: float
		if b < 0.0:
			f = lerpf(0.0, FLIP_GRAB, clampf((b + FLIP_REACH) / FLIP_REACH, 0.0, 1.0))
		elif b < 1.0:
			f = lerpf(FLIP_GRAB, FLIP_TOP, b)
		elif b < 2.0:
			f = lerpf(FLIP_TOP, FLIP_LAND, b - 1.0)
		elif b < 2.0 + FLIP_RETURN:
			f = lerpf(FLIP_LAND, FLIP_END, (b - 2.0) / FLIP_RETURN)
		else:
			_flips.erase(who)
			f = 0.0
		if who.animation != &"flip":
			who.animation = &"flip"
		who.stop()
		who.frame = int(f)


func _sound(cue: String, part: int) -> void:
	var key := "tong"
	if cue != "tap":
		key = ["flip", "scrape", "pop" if cue == "pop" else "sizzle"][clampi(part, 0, 2)]
	if not _sfx.has(key):
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = _sfx[key]
	p.play()


# --- drawing -----------------------------------------------------------------------

func _draw_fx() -> void:
	var now := Conductor.song_position
	var font := ThemeDB.fallback_font
	var l := _fx_layer
	if _landed:
		_draw_burger(l, bun_pos)
	if _example_landed:
		_draw_burger(l, example_bun_pos)
	for f in _fx:
		var t: float = now - f["t0"]
		var pos: Vector2 = f["pos"]
		match f["kind"]:
			"steam":   # three puffs drifting up off the patty
				for i in 3:
					var p := pos + Vector2((i - 1) * 26.0 + sin(t * 6.0 + i) * 6.0, -30.0 - t * 90.0 - i * 10.0)
					l.draw_circle(p, 10.0 + t * 14.0, Color(0.85, 0.85, 0.85, clampf(0.7 - t * 0.9, 0.0, 1.0)))
			"pop":     # burst where the patty lands
				for i in 8:
					var a := TAU * i / 8.0
					l.draw_circle(pos + Vector2(cos(a), sin(a)) * (20.0 + t * 160.0) + Vector2(0, -30),
						6.0 * (1.0 - clampf(t, 0.0, 1.0)), Color(1, 0.85, 0.3, clampf(1.0 - t, 0.0, 1.0)))
			"miss":    # brief smoky puff: burnt
				l.draw_circle(pos + Vector2(0, -20 - t * 40.0), 18.0 + t * 30.0, Color(0.3, 0.3, 0.3, clampf(0.6 - t, 0.0, 1.0)))

	if _phase == Phase.SONG:
		l.draw_string(font, Vector2(VP.x - 250, 52), "SCORE  %d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, INK)
		l.draw_string(font, Vector2(VP.x - 250, 88), "COMBO  x%d" % combo, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)
	else:
		_draw_practice(l, font)
	if banner != "":
		l.draw_string_outline(font, Vector2(0, VP.y * 0.42), banner, HORIZONTAL_ALIGNMENT_CENTER, VP.x, 56, 8, Color(0.15, 0.1, 0.08))
		l.draw_string(font, Vector2(0, VP.y * 0.42), banner, HORIZONTAL_ALIGNMENT_CENTER, VP.x, 56, Color.WHITE)
	if _finished:
		_draw_results(l, font)


func _draw_practice(l: Node2D, font: Font) -> void:
	# "YOU" over your tongs
	var tip := you_pos
	l.draw_string_outline(font, Vector2(tip.x - 100, tip.y - 40), "YOU", HORIZONTAL_ALIGNMENT_CENTER, 200, 44, 8, Color(0.15, 0.1, 0.08))
	l.draw_string(font, Vector2(tip.x - 100, tip.y - 40), "YOU", HORIZONTAL_ALIGNMENT_CENTER, 200, 44, Color(1, 0.95, 0.45))
	l.draw_colored_polygon(PackedVector2Array([tip + Vector2(-13, -30), tip + Vector2(13, -30), tip]), Color(1, 0.95, 0.45))

	var box := Rect2(VP.x - 400, VP.y - 216, 376, 196)   # bottom-right: clear of the grill and both tongs
	var x := box.position.x
	var y := box.position.y
	var w := box.size.x
	l.draw_style_box(_panel_sb, box)
	l.draw_string(font, Vector2(x, y + 46), "PRACTICE", HORIZONTAL_ALIGNMENT_CENTER, w, 32, INK)
	l.draw_string(font, Vector2(x, y + 82), "Copy the blue tongs with SPACE", HORIZONTAL_ALIGNMENT_CENTER, w, 22, INK)
	var step_text := "Clack clack!" if _step == 0 else "Flip: 3 presses, beats 1-2-3"
	l.draw_string(font, Vector2(x, y + 114), step_text, HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color(0.25, 0.4, 0.75))
	var gap := 44.0
	var cx := x + w * 0.5 - gap * (practice_goal - 1) * 0.5
	for i in practice_goal:
		var c := Vector2(cx + gap * i, y + 146)
		if i < _step_ok or _phase == Phase.TRANSITION:
			l.draw_circle(c, 14.0, Color(0.36, 0.62, 0.32))
		else:
			l.draw_arc(c, 14.0, 0.0, TAU, 32, Color(INK, 0.45), 3.0)
	l.draw_string(font, Vector2(x, y + 184), "S to skip", HORIZONTAL_ALIGNMENT_CENTER, w, 16, Color(INK, 0.6))


## Placeholder bun + patty until there's art for it.
func _draw_burger(l: Node2D, b: Vector2) -> void:
	l.draw_set_transform(b + Vector2(0, 18), 0.0, Vector2(1.0, 0.35))
	l.draw_circle(Vector2.ZERO, 90.0, Color(0.87, 0.62, 0.3))             # bottom bun
	l.draw_set_transform(b, 0.0, Vector2(1.0, 0.3))
	l.draw_circle(Vector2.ZERO, 84.0, Color(0.36, 0.2, 0.12))              # patty
	l.draw_set_transform(b + Vector2(0, -26), 0.0, Vector2(1.0, 0.55))
	l.draw_circle(Vector2.ZERO, 88.0, Color(0.93, 0.68, 0.33))             # top bun
	l.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for s in [Vector2(-40, -56), Vector2(0, -66), Vector2(38, -54), Vector2(-14, -44), Vector2(20, -40)]:
		l.draw_circle(b + s, 4.0, Color(1, 0.96, 0.85))                   # sesame


func _draw_results(l: Node2D, font: Font) -> void:
	var box := Rect2(VP.x / 2 - 200, VP.y / 2 - 120, 400, 240)
	l.draw_rect(box, Color(0, 0, 0, 0.6))
	var x := box.position.x + 32
	var y := box.position.y + 54
	l.draw_string(font, Vector2(x, y), "RESULTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
	l.draw_string(font, Vector2(x, y + 50), "Perfect   %d" % _tally["Perfect"], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.7, 1.0, 0.6))
	l.draw_string(font, Vector2(x, y + 82), "Good      %d" % _tally["Good"], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.9, 0.5))
	l.draw_string(font, Vector2(x, y + 114), "Miss      %d" % _tally["Miss"], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.5, 0.5))
	l.draw_string(font, Vector2(x, y + 154), "Score %d   Best x%d" % [score, best_combo], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	l.draw_string(font, Vector2(x, y + 186), "R to replay  -  Esc for menu", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.8, 0.8))
