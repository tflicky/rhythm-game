extends Node2D
## Root of the level scene.
##   mode PLAY   : a practice round in two checkpoints -- catch practice_goal
##                 coconuts cleanly, then banana_goal bananas -- then the beatmap
##                 feeds the coconut minigame.
##   mode RECORD : you tap the cue times yourself and save them into the beatmap.
## Press F2 at runtime to switch modes (restarts the song).

enum Mode { PLAY, RECORD }
enum Phase { DEMO, PRACTICE, TRANSITION, SONG }

## Drag a Beatmap .tres here (defaults to rhythm_monkey.tres).
@export var beatmap: Beatmap
@export var mode: Mode = Mode.PLAY
@export var autostart: bool = true

@export_group("Practice round")
## Start each play session with a practice round. Turn off to jump straight into the song.
@export var practice: bool = true
## Before practice, show how it's played: one coconut falls and the monkey catches it by himself.
@export var demo: bool = true
## Seconds after the demo catch before practice starts.
@export var demo_outro: float = 1.2
## Clean (Perfect) coconut catches needed for the first checkpoint.
@export var practice_goal: int = 3
## Clean (Perfect) banana catches needed for the second (bananas come in pairs).
@export var banana_goal: int = 4
## A practice coconut lands every this many beats...
@export var practice_every: float = 4.0
## ...starting on this beat.
@export var practice_first_beat: float = 4.0
## Practice runs over a metronome (not the song) this many beats long, then loops.
@export var practice_metronome_beats: int = 64
@export var practice_metronome_db: float = -8.0
## Seconds between passing a checkpoint and the next one (or the song) starting,
## so the fruit already in the air comes down first.
@export var practice_outro: float = 1.5

@onready var audio: AudioStreamPlayer = $AudioStreamPlayer
@onready var game: Node2D = $CoconutGame
@onready var recorder: Node2D = $ChartRecorder

var _cues: Array = []
var _phase := Phase.SONG
var _practice_passed := false   ## once passed, R replays the song without practice
var _song_stream: AudioStream
var _metronome: AudioStreamWAV
var _practice_kind := "catch"   ## the checkpoint being practised: "catch" (coconuts), then "banana"


var _pause: PauseMenu

func _ready() -> void:
	_pause = PauseMenu.attach(self, _restart)   # Esc: Continue / Retry / Quit
	Conductor.stream_player = audio
	_song_stream = audio.stream

	if beatmap:
		Conductor.bpm = beatmap.bpm
		Conductor.first_beat_offset = beatmap.first_beat_offset
		Conductor.video_offset = beatmap.video_offset
		# this computer's calibration (main menu -> Calibrate timing) wins
		Conductor.input_offset = Settings.input_offset(beatmap.input_offset)
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
		if demo:
			_start_demo()
		else:
			_start_practice()
	else:
		_start_song()


## The "watch" demo: one coconut on the practice metronome, caught by the game itself.
func _start_demo() -> void:
	_phase = Phase.DEMO
	_practice_kind = "catch"
	game.practice = true
	game.demo = true
	game.practice_kind = "catch"
	game.practice_caught = 0
	game.banner = ""
	if _metronome == null:
		_metronome = ClickTrack.make(Conductor.bpm, practice_metronome_beats, Conductor.beats_per_measure, Conductor.first_beat_offset)
	audio.stream = _metronome
	audio.volume_db = practice_metronome_db
	Conductor.play()
	game.begin([{"beat": practice_first_beat, "cue": "catch", "length": 0.0, "time": Conductor.time_of_beat(practice_first_beat)}])


func _start_practice(kind := "catch") -> void:
	_phase = Phase.PRACTICE
	_practice_kind = kind
	game.practice = true
	game.demo = false
	game.practice_kind = kind
	game.practice_goal = practice_goal if kind == "catch" else banana_goal
	game.practice_caught = 0
	game.banner = ""
	if _metronome == null:
		_metronome = ClickTrack.make(Conductor.bpm, practice_metronome_beats, Conductor.beats_per_measure, Conductor.first_beat_offset)
	audio.stream = _metronome
	audio.volume_db = practice_metronome_db
	Conductor.play()
	game.begin(_practice_cues())


## One coconut (or one banana pair, a beat apart) every practice_every beats
## across the metronome track; it loops until the player gets enough clean catches.
func _practice_cues() -> Array:
	var out: Array = []
	var song_beats := float(practice_metronome_beats)
	var b := practice_first_beat
	while b < song_beats - 2.0:
		var beats := [b] if _practice_kind == "catch" else [b, b + 1.0]
		for x in beats:
			out.append({"beat": x, "cue": _practice_kind, "length": 0.0, "time": Conductor.time_of_beat(x)})
		b += practice_every
	return out


func _start_song() -> void:
	_phase = Phase.SONG
	game.practice = false
	game.demo = false
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
	if _phase == Phase.DEMO:
		_phase = Phase.TRANSITION
		await get_tree().create_timer(demo_outro).timeout
		if _phase == Phase.TRANSITION:   # not skipped with S / R in the meantime
			_start_practice()
		return
	if _phase != Phase.PRACTICE or grade != "Perfect":
		return
	game.practice_caught += 1
	if game.practice_caught < game.practice_goal:
		return
	# Checkpoint passed: nothing new falls, the fruit in the air comes down, then
	# the banana checkpoint -- or, after that, the real song from the top.
	_phase = Phase.TRANSITION
	var next := "banana" if _practice_kind == "catch" else ""
	if next == "":
		_practice_passed = true
	game.stop_spawning()
	await get_tree().create_timer(practice_outro).timeout
	if _phase != Phase.TRANSITION:   # interrupted by R / S / F2 in the meantime
		return
	if next == "":
		_start_song()
	else:
		_start_practice(next)


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
			if _phase in [Phase.DEMO, Phase.PRACTICE, Phase.TRANSITION]:
				_practice_passed = true
				_start_song()
		KEY_ESCAPE:
			if game._finished:          # results screen: straight to the menu
				get_tree().change_scene_to_file("res://MainMenu.tscn")
			else:
				_pause.open()
			get_viewport().set_input_as_handled()
		KEY_F2:
			mode = Mode.RECORD if mode == Mode.PLAY else Mode.PLAY
			_apply_mode()
			_restart()
			print("[rhythm] mode -> ", "RECORD" if mode == Mode.RECORD else "PLAY")
