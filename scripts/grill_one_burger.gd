extends Node2D
## One-Burger Test: is flipping ONE burger on the beat fun?
##
## A loop, every `cycle_beats` beats:
##   spawn beat        a raw patty lands on the grill        (sizzle)
##   each beat after   it cooks                              (sizzle, sizzle, ...)
##   target beat       it's ready -- FLIP NOW                (POP)
## Sizzle means get ready, pop means flip. Press SPACE (or click) on the pop.
##   Perfect / Good  : flipped on time, nicely browned
##   Early           : flipped too soon -- still raw
##   Late            : flipped too late, or never -- burnt
## Then the patty comes off and a fresh one goes on. It loops forever (the song
## restarts when it ends), so you can test over and over.
##
## Timing: everything reads the Conductor autoload (audio playback clock). Cue
## sounds are triggered output-latency early so you HEAR them on the beat; presses
## are graded with Conductor.timing_error(), which removes Conductor.input_offset.
## Tempo comes from the beatmap (beatmaps/grill.tres, 130 BPM); its cue list is
## not used by this test.
##   Space / click  flip     R  restart     Esc  menu

enum State { EMPTY, COOKING, FLIPPED }

const GRILL_GAME := preload("res://scripts/grill_game.gd")   ## for load_sound()
const FLIP_FRAMES := 28
const FLIP_START := 5          ## frame the flip starts from when you press (tongs already reaching)
const FLIP_LAND := 19          ## frame the patty lands back on the grill
const FLIP_END := 27           ## tongs back at rest
const RAW_PINK := Color(0.93, 0.45, 0.47)
const BURNT := Color(0.16, 0.09, 0.06)
const GRADE_TEXT := {
	"Perfect": "PERFECT!", "Good": "GOOD",
	"Early": "EARLY -- raw!", "Late": "LATE -- burnt!", "Miss": "TOO LATE -- burnt!",
}
const GRADE_COL := {
	"Perfect": Color(1.0, 0.72, 0.1), "Good": Color(0.3, 0.68, 0.3),
	"Early": Color(0.9, 0.42, 0.5), "Late": Color(0.45, 0.25, 0.15), "Miss": Color(0.45, 0.25, 0.15),
}
const POINTS := {"Perfect": 100, "Good": 50, "Early": 0, "Late": 0, "Miss": 0}

@export var beatmap: Beatmap

@export_group("Loop")
## Beat the first burger goes on (gives a bar of lead-in).
@export var first_spawn_beat: int = 4
## Beats from placing the burger to its flip (the pop). Sizzles fill the beats before.
@export var flip_after_beats: int = 4
## Beats from one burger going on to the next one. Must be > flip_after_beats + 1.
@export var cycle_beats: int = 8
## Beats after the target the flipped / burnt patty stays before it's cleared.
@export var linger_beats: float = 2.0

@export_group("Timing windows (seconds, +/- around the pop)")
@export var perfect_window: float = 0.05
@export var good_window: float = 0.12
## Presses earlier than good_window but within this are Early (raw). Earlier
## presses are ignored (just a tong click).
@export var early_window: float = 0.3
## Presses later than good_window but within this are Late (burnt). No press by
## then = also burnt.
@export var late_window: float = 0.3

@export_group("Audio")
## Off = a generated metronome instead of the grill song.
@export var use_song: bool = true
@export var metronome_beats: int = 64
@export var sizzle_db: float = -6.0
@export var pop_db: float = 0.0
@export var music_db: float = -6.0

@onready var audio: AudioStreamPlayer = $AudioStreamPlayer
@onready var tongs: AnimatedSprite2D = $Stage/Tongs
@onready var bare_tongs: Sprite2D = $Stage/BareTongs
@onready var judge_label: Label = $HUD/Judge
@onready var score_label: Label = $HUD/Score
@onready var info_label: Label = $HUD/Info

var score := 0
var streak := 0
var tally := {"Perfect": 0, "Good": 0, "Early": 0, "Late": 0}
## Every graded burger, oldest first: { beat, grade, err } -- handy for tests.
var results: Array = []

var _song: AudioStream
var _metronome: AudioStreamWAV
var _sfx := {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _cook: ShaderMaterial

var _state := State.EMPTY
var _spawn_beat := 0           ## beat the current / next burger goes on
var _next_sound := 0           ## index into this cycle's cue sounds still to schedule
var _flip_t0 := -1.0           ## song time the flip press happened (-1: none)
var _raw_target := 1.0
var _judge_ms := -10000


func _ready() -> void:
	_song = audio.stream
	Conductor.stream_player = audio
	if beatmap:
		Conductor.bpm = beatmap.bpm
		Conductor.first_beat_offset = beatmap.first_beat_offset
		Conductor.video_offset = beatmap.video_offset
		Conductor.input_offset = Settings.input_offset(beatmap.input_offset)
	Conductor.song_finished.connect(_on_song_finished)
	cycle_beats = maxi(cycle_beats, flip_after_beats + 2)

	# your sound files in audio/sfx/grill/ (see its README): the per-beat
	# "cook_sizzle" cue, the "pop" cue, and the "tong" click
	var dir := "res://audio/sfx/grill/"
	for k in ["pop", "tong"]:
		var s := GRILL_GAME.load_sound(dir, k)
		if s:
			_sfx[k] = s
	var sizzle := GRILL_GAME.load_sound(dir, "cook_sizzle")
	if sizzle == null:
		print("[grill-test] placeholder sound still in use (make %scook_sizzle.wav)" % dir)
		sizzle = _synth_sizzle()   # until then: a short hiss that hits at once
	_sfx["sizzle"] = sizzle
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

	var frames := SpriteFrames.new()
	frames.add_animation(&"flip")
	frames.set_animation_loop(&"flip", false)
	for i in FLIP_FRAMES:
		frames.add_frame(&"flip", load("res://art/grilling/flip/flip_%02d.png" % i))
	tongs.sprite_frames = frames
	tongs.animation = &"flip"
	tongs.frame = 0
	_cook = ShaderMaterial.new()
	_cook.shader = preload("res://shaders/patty_cook.gdshader")
	tongs.material = _cook

	_start()


## Conductor is an autoload and outlives this scene -- stop it before our
## AudioStreamPlayer is freed.
func _exit_tree() -> void:
	Conductor.song_finished.disconnect(_on_song_finished)
	Conductor.stop()
	Conductor.stream_player = null


func _start() -> void:
	if use_song and _song:
		audio.stream = _song
	else:
		if _metronome == null:
			_metronome = ClickTrack.make(Conductor.bpm, metronome_beats, Conductor.beats_per_measure, Conductor.first_beat_offset)
		audio.stream = _metronome
	audio.volume_db = music_db
	_spawn_beat = first_spawn_beat
	_next_sound = 0
	_clear_burger()
	Conductor.play()
	_update_hud()


func _on_song_finished() -> void:
	_start()   # loop: the clock must never jump back mid-song, so restart from the top


func _process(_delta: float) -> void:
	if not Conductor.playing:
		return
	_schedule_sounds()

	var beat_now: float = Conductor.song_position_in_beats
	var target := _target_beat()
	match _state:
		State.EMPTY:
			if beat_now >= _spawn_beat:
				_spawn()
		State.COOKING:
			# never pressed: once the late window has passed, it's burnt
			if Conductor.live_position() - Conductor.input_offset > Conductor.time_of_beat(target) + late_window:
				_judge("Miss", late_window)
		State.FLIPPED:
			pass
	if _state != State.EMPTY and beat_now >= target + linger_beats:
		_clear_burger()
		_spawn_beat += cycle_beats
		_next_sound = 0
	_animate()


## Cue sounds go out output-latency early, so they're HEARD on the beat.
## Sizzle on the spawn beat and every beat after, pop on the target.
func _schedule_sounds() -> void:
	var heard_at: float = Conductor.song_position + AudioServer.get_output_latency()
	while _next_sound <= flip_after_beats:
		var b := _spawn_beat + _next_sound
		var t := Conductor.time_of_beat(b)
		if heard_at < t:
			return
		_next_sound += 1
		if heard_at - t > 0.1:
			continue   # way behind (e.g. a hitch): don't play a late cue
		if b == _target_beat():
			_play("pop", pop_db)
		else:
			_play("sizzle", sizzle_db)


func _target_beat() -> int:
	return _spawn_beat + flip_after_beats


func _spawn() -> void:
	_state = State.COOKING
	_flip_t0 = -1.0
	_raw_target = 1.0
	_cook.set_shader_parameter("raw_color", RAW_PINK)
	_cook.set_shader_parameter("raw", 1.0)
	tongs.frame = 0
	tongs.visible = true
	bare_tongs.visible = false


func _clear_burger() -> void:
	_state = State.EMPTY
	_flip_t0 = -1.0
	tongs.visible = false
	bare_tongs.visible = true


func _unhandled_input(e: InputEvent) -> void:
	var pressed: bool = (e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_SPACE) \
		or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
	if pressed:
		_press()
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_R:
				score = 0
				streak = 0
				for k in tally:
					tally[k] = 0
				results.clear()
				judge_label.text = ""
				_start()
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://MainMenu.tscn")


func _press() -> void:
	if _state != State.COOKING:
		_play("tong", -10.0)
		return
	var err: float = Conductor.timing_error(_target_beat())
	if err < -early_window:
		_play("tong", -10.0)   # way too soon: not a flip yet
		return
	var grade := "Perfect"
	if absf(err) > good_window:
		grade = "Early" if err < 0.0 else "Late"
	elif absf(err) > perfect_window:
		grade = "Good"
	_flip_t0 = Conductor.live_position()
	_judge(grade, err)


func _judge(grade: String, err: float) -> void:
	_state = State.FLIPPED
	var tallied := "Late" if grade == "Miss" else grade
	tally[tallied] += 1
	score += POINTS[grade]
	streak = streak + 1 if grade == "Perfect" or grade == "Good" else 0
	results.append({"beat": _target_beat(), "grade": grade, "err": err})
	match grade:
		"Perfect":
			_raw_target = 0.0
		"Good":
			_raw_target = 0.15
		"Early":
			_raw_target = 0.75
		_:
			_cook.set_shader_parameter("raw_color", BURNT)
			_raw_target = 0.85
	judge_label.text = GRADE_TEXT[grade]
	judge_label.add_theme_color_override("font_color", GRADE_COL[grade])
	_judge_ms = Time.get_ticks_msec()
	info_label.text = "no press" if grade == "Miss" else "%+d ms" % roundi(err * 1000.0)
	print("[grill-test] beat %d: %s (%s)" % [_target_beat(), grade, info_label.text])
	_update_hud()


func _update_hud() -> void:
	score_label.text = "Score %d   Streak %d\nPerfect %d  Good %d  Early %d  Late %d" % [
		score, streak, tally["Perfect"], tally["Good"], tally["Early"], tally["Late"]]


func _animate() -> void:
	# patty colour: browns while it cooks, then eases to the result
	if _state == State.COOKING:
		var p := clampf((Conductor.song_position_in_beats - _spawn_beat) / flip_after_beats, 0.0, 1.0)
		_cook.set_shader_parameter("raw", lerpf(1.0, 0.6, p))
	elif _state == State.FLIPPED:
		var cur: float = _cook.get_shader_parameter("raw")
		_cook.set_shader_parameter("raw", lerpf(cur, _raw_target, 0.2))

	# the flip: driven by the music clock from the press -- up and over in one
	# beat, back to rest in another half
	if _flip_t0 >= 0.0:
		var b := (Conductor.visual_position - _flip_t0) / Conductor.seconds_per_beat
		if b < 1.0:
			tongs.frame = int(lerpf(FLIP_START, FLIP_LAND, b))
		else:
			tongs.frame = int(lerpf(FLIP_LAND, FLIP_END, clampf((b - 1.0) / 0.5, 0.0, 1.0)))

	# judgement text pops in, then fades
	var age := (Time.get_ticks_msec() - _judge_ms) / 1000.0
	judge_label.scale = Vector2.ONE * (1.0 + 0.25 * maxf(0.0, 1.0 - age * 6.0))
	judge_label.modulate.a = clampf(2.0 - age, 0.0, 1.0)


## A short hiss: high-passed noise, 2 ms attack, gone in ~0.2 s.
func _synth_sizzle() -> AudioStreamWAV:
	var rate := 44100
	var n := int(0.22 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.3
		var v := (x - lp) * exp(-t * 16.0) * clampf(t / 0.002, 0.0, 1.0)
		data.encode_s16(i * 2, int(clampf(v * 0.9, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


func _play(key: String, db: float) -> void:
	if not _sfx.has(key):
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = _sfx[key]
	p.volume_db = db
	p.play()
