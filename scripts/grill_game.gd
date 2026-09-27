extends Node2D
## "Grill Master" minigame -- test bed for now.
## Space / left-click plays the tong tap, F / right-click plays the flip
## (either restarts from frame 0 if something is mid-animation).
## The song runs through the Conductor at 128 BPM so you can tap along;
## M toggles a metronome click, R restarts the song, Esc goes back to the menu.

@export var bpm: float = 128.0
@export var metronome: bool = true

@onready var audio: AudioStreamPlayer = $AudioStreamPlayer
@onready var tongs: AnimatedSprite2D = $Stage/Tongs

var _click: AudioStreamPlayer


func _ready() -> void:
	tongs.animation = &"flip"
	tongs.frame = 0

	_click = AudioStreamPlayer.new()
	_click.stream = _make_click(1000.0, 0.05)
	add_child(_click)

	Conductor.stream_player = audio
	Conductor.bpm = bpm
	Conductor.first_beat_offset = 0.0
	Conductor.beat.connect(_on_beat)
	Conductor.play()


## Conductor is an autoload and outlives this scene -- stop it before our
## AudioStreamPlayer is freed, or its _process would poke a dead node.
func _exit_tree() -> void:
	Conductor.beat.disconnect(_on_beat)
	Conductor.stop()
	Conductor.stream_player = null


func _on_beat(_i: int) -> void:
	if metronome:
		_click.play()


func _play(anim: StringName) -> void:
	tongs.stop()
	tongs.play(anim)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_echo():
		return
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_play(&"tap")
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			_play(&"flip")
	elif e is InputEventKey and e.pressed:
		match e.keycode:
			KEY_SPACE:
				_play(&"tap")
			KEY_F:
				_play(&"flip")
			KEY_M:
				metronome = not metronome
			KEY_R:
				Conductor.play()
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://MainMenu.tscn")


## Short procedural sine "tick" so the metronome needs no audio asset.
func _make_click(freq: float, seconds: float) -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := pow(1.0 - float(i) / n, 2.0)
		var s := sin(TAU * freq * t) * env * 0.5
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
