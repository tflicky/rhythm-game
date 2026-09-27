extends Node2D
## Root of the level scene.
##   mode PLAY   : a practice round (catch practice_goal coconuts cleanly), then
##                 the beatmap feeds the coconut minigame.
##   mode RECORD : you tap the cue times yourself and save them into the beatmap.
## Press F2 at runtime to switch modes (restarts the song).

enum Mode { PLAY, RECORD }
enum Phase { PRACTICE, TRANSITION, SONG }

## Drag a Beatmap .tres here (defaults to rhythm_monkey.tres).
@export var beatmap: Beatmap
@export var mode: Mode = Mode.PLAY
@export var autostart: bool = true

@export_group("Practice round")
## Start each play session with a practice round. Turn off to jump straight into the song.
@export var practice: bool = true
## Clean (Perfect) catches needed to finish practice.
@export var practice_goal: int = 3
## A practice coconut lands every this many beats...
@export var practice_every: float = 4.0
## ...starting on this beat.
@export var practice_first_beat: float = 4.0
## Practice runs over a metronome (not the song) this many beats long, then loops.
@export var practice_metronome_beats: int = 64
@export var practice_metronome_db: float = -8.0
## Seconds the "here we go" banner shows before the song starts.
@export var practice_outro: float = 2.0

@onready var audio: AudioStreamPlayer = $AudioStreamPlayer
@onready var game: Node2D = $CoconutGame
@onready var recorder: Node2D = $ChartRecorder

var _cues: Array = []
var _phase := Phase.SONG
var _practice_passed := false   ## once passed, R replays the song without practice
var _song_stream: AudioStream
var _metronome: AudioStreamWAV


func _ready() -> void:
	Conductor.stream_player = audio
	_song_stream = audio.stream

	if beatmap:
		Conductor.bpm = beatmap.bpm
		Conductor.first_beat_offset = beatmap.first_beat_offset
		Conductor.video_offset = beatmap.video_offset
		Conductor.input_offset = beatmap.input_offset
		_cues = beatmap.compiled(Conductor)
		print("[rhythm] loaded '%s': %d cues @ %.1f BPM" % [
			beatmap.song_title, _cues.size(), beatmap.bpm])
	else:
		push_warning("[rhythm] no beatmap assigned; using Conductor defaults")

	game.graded.connect(_on_graded)
	Conductor.song_finished.connect(_on_song_finished)

	_apply_mode()
	if autostart:
		_restart()


## Conductor is an autoload and outlives this scene -- stop it before our
## AudioStreamPlayer is freed, or its _process would poke a dead node.
func _exit_tree() -> void:
	Conductor.song_finished.disconnect(_on_song_finished)
	Conductor.stop()
	Conductor.stream_player = null


func _apply_mode() -> void:
	var play := mode == Mode.PLAY
	_set_active(game, play)
	_set_active(recorder, not play)


func _set_active(n: Node2D, on: bool) -> void:
	n.visible = on
	n.set_process(on)
	n.set_process_unhandled_input(on)


func _restart() -> void:
	if mode == Mode.PLAY and practice and not _practice_passed:
		_start_practice()
	else:
		_start_song()


func _start_practice() -> void:
	_phase = Phase.PRACTICE
	game.practice = true
	game.practice_goal = practice_goal
	game.practice_caught = 0
	game.banner = ""
	if _metronome == null:
		_metronome = _make_metronome()
	audio.stream = _metronome
	audio.volume_db = practice_metronome_db
	Conductor.play()
	game.begin(_practice_cues())


## One coconut every practice_every beats across the metronome track; it loops
## until the player gets enough clean catches.
func _practice_cues() -> Array:
	var out: Array = []
	var song_beats := float(practice_metronome_beats)
	var b := practice_first_beat
	while b < song_beats - 1.0:
		out.append({"beat": b, "cue": "catch", "length": 0.0, "time": Conductor.time_of_beat(b)})
		b += practice_every
	return out


func _start_song() -> void:
	_phase = Phase.SONG
	game.practice = false
	game.banner = ""
	audio.stream = _song_stream
	audio.volume_db = 0.0
	# Rebuild cues in case the recorder just saved new ones.
	if beatmap and mode == Mode.PLAY:
		_cues = beatmap.compiled(Conductor)
	Conductor.play()
	if mode == Mode.PLAY:
		game.begin(_cues)
	else:
		recorder.begin()


func _on_graded(grade: String) -> void:
	if _phase != Phase.PRACTICE or grade != "Perfect":
		return
	game.practice_caught += 1
	if game.practice_caught < practice_goal:
		return
	# Passed: nothing new falls, cheer, then the real song from the top.
	_phase = Phase.TRANSITION
	_practice_passed = true
	game.stop_spawning()
	game.banner = "Nice! Here we go!"
	await get_tree().create_timer(practice_outro).timeout
	if _phase == Phase.TRANSITION:   # not interrupted by R / F2 in the meantime
		_start_song()


func _on_song_finished() -> void:
	if _phase == Phase.PRACTICE:
		Conductor.play()               # keep practising: the metronome starts over
		game.begin(_practice_cues())


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match e.keycode:
		KEY_R:
			_restart()
		KEY_S:
			# skip practice (S is the recorder's save key in RECORD mode -- phase is SONG there)
			if _phase == Phase.PRACTICE or _phase == Phase.TRANSITION:
				_practice_passed = true
				_start_song()
		KEY_ESCAPE:
			get_tree().change_scene_to_file("res://MainMenu.tscn")
		KEY_F2:
			mode = Mode.RECORD if mode == Mode.PLAY else Mode.PLAY
			_apply_mode()
			_restart()
			print("[rhythm] mode -> ", "RECORD" if mode == Mode.RECORD else "PLAY")


## Practice click track at the song's BPM: a high tick on each bar's downbeat,
## a lower one on the other beats. Not looped -- song_finished restarts it, so
## the Conductor clock never jumps backwards.
func _make_metronome() -> AudioStreamWAV:
	var rate := 44100
	var spb: float = Conductor.seconds_per_beat
	var n := int(rate * (spb * practice_metronome_beats + 0.5))
	var data := PackedByteArray()
	data.resize(n * 2)   # zero-filled = silence
	var click_n := int(rate * 0.04)
	for b in practice_metronome_beats:
		var freq := 1600.0 if b % Conductor.beats_per_measure == 0 else 1000.0
		var start := int(rate * (Conductor.first_beat_offset + b * spb))
		for i in click_n:
			var t := float(i) / rate
			var env := pow(1.0 - float(i) / click_n, 3.0)
			data.encode_s16((start + i) * 2, int(sin(TAU * freq * t) * env * 0.6 * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
