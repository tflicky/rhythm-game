extends Node
## Central rhythm clock (autoload singleton, registered as "Conductor").
##
## Every gameplay system reads the song position / current beat from HERE, and
## this value is derived from the audio hardware clock -- never from Timer nodes
## or accumulated _process(delta). That is what keeps visuals, cues and hit
## detection locked together even when the framerate stutters.
##
## Usage:
##   Conductor.stream_player = $AudioStreamPlayer   # assign once
##   Conductor.bpm = 128.0
##   Conductor.first_beat_offset = 0.0              # measured from the WAV
##   Conductor.play()
##   Conductor.beat.connect(_on_beat)

signal song_started
signal song_finished
## Fired once as the song crosses each whole beat. beat_index 0 == bar 1, beat 1.
signal beat(beat_index: int)
## Fired on every half beat (8th notes). half_index 0 lines up with beat 0.
signal half_beat(half_index: int)
## Fired on the downbeat of each bar. measure_index 0 == the first bar.
signal measure(measure_index: int)

## Tempo the track was written at. Must be constant across the whole song.
@export var bpm: float = 128.0
@export var beats_per_measure: int = 4
## Seconds into the WAV where beat 0 (bar 1, beat 1) lands. Measure this against
## the waveform. Nudge it live with the Up/Down arrows in the debug overlay.
@export var first_beat_offset: float = 0.0
## Extra manual latency trim, seconds, applied on top of the measured output
## latency. Nudge live with [ and ] in the debug overlay. +ve = game treats
## "now" as later (use if the click feels early against the music).
@export var calibration_offset: float = 0.0
## Per-player INPUT latency, seconds. How late this player's taps land relative
## to the beat they hear (keyboard + reaction + OS queue). Applied ONLY to input
## grading, never to the audio clock or visuals. Auto-set from taps with C in the
## debug overlay. +ve = player is late; grading subtracts it.
@export var input_offset: float = 0.0
## DISPLAY latency, seconds. The frames you SEE lag the audio you HEAR by this
## much (render pipeline + monitor). Rendering code reads `visual_position`
## instead of `song_position` so visuals are drawn this far AHEAD and line up on
## screen. Affects DRAWING ONLY -- not input grading, not the beat signals.
## Nudge live with , and . in the debug overlay. +ve = draw visuals earlier.
@export var video_offset: float = 0.0

## Assign this before calling play().
var stream_player: AudioStreamPlayer

var playing: bool = false
## Seconds from the very start of the WAV, aligned to what you are hearing now.
var song_position: float = 0.0
## song_position expressed in beats. Negative while inside the lead-in.
var song_position_in_beats: float = 0.0

var seconds_per_beat: float:
	get:
		return 60.0 / bpm

## Song position that RENDERING should use: the audio clock plus video_offset,
## so on-screen visuals land in sync with the sound after display lag. Gameplay
## logic and input grading keep using song_position.
var visual_position: float:
	get:
		return song_position + video_offset

var _last_beat: int = -1
var _last_half: int = -1


func _ready() -> void:
	set_process(false)


## from_beat lets you start partway into the chart while practising.
func play(from_beat: float = 0.0) -> void:
	assert(stream_player != null, "Conductor.stream_player must be set before play()")
	_reset()
	var start_seconds: float = maxf(first_beat_offset + from_beat * seconds_per_beat, 0.0)
	stream_player.play(start_seconds)
	playing = true
	set_process(true)
	song_started.emit()


func stop() -> void:
	if is_instance_valid(stream_player) and stream_player.playing:
		stream_player.stop()
	playing = false
	set_process(false)


func _process(_delta: float) -> void:
	if not playing:
		return

	if not stream_player.playing:
		playing = false
		set_process(false)
		song_finished.emit()
		return

	# Keep the reported clock monotonic so the live readout never wobbles
	# backwards at a buffer boundary. Crossing detection is forward-only anyway.
	song_position = maxf(song_position, _raw_position())
	song_position_in_beats = (song_position - first_beat_offset) / seconds_per_beat

	_emit_crossings()


## The standard Godot rhythm-game formula: playback position of the current
## audio buffer, plus time elapsed since that buffer was mixed, minus the
## hardware output latency, minus our manual trim.
func _raw_position() -> float:
	return stream_player.get_playback_position() \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency() \
		- calibration_offset


## The audio clock sampled right NOW, not at the last _process. Input events are
## handled before _process each frame, so song_position is up to a frame stale
## when a key press is graded -- use this for grading instead.
func live_position() -> float:
	if not playing:
		return song_position
	return maxf(song_position, _raw_position())


func _emit_crossings() -> void:
	var whole: int = int(floor(song_position_in_beats))
	while _last_beat < whole:
		_last_beat += 1
		beat.emit(_last_beat)
		if _last_beat % beats_per_measure == 0:
			@warning_ignore("integer_division")
			measure.emit(_last_beat / beats_per_measure)

	var half: int = int(floor(song_position_in_beats * 2.0))
	while _last_half < half:
		_last_half += 1
		half_beat.emit(_last_half)


func _reset() -> void:
	_last_beat = -1
	_last_half = -1
	song_position = 0.0
	song_position_in_beats = 0.0


## --- helpers for beatmap / gameplay code -------------------------------------

## Seconds at which a given (possibly fractional) beat occurs in the WAV.
func time_of_beat(beat_number: float) -> float:
	return first_beat_offset + beat_number * seconds_per_beat


## Signed timing error, in seconds, between an input NOW and a target beat, with
## the player's input latency compensated out. Use this to grade taps.
## Negative = early, positive = late.
func timing_error(target_beat: float) -> float:
	return live_position() - input_offset - time_of_beat(target_beat)


## Same, but WITHOUT input_offset compensation -- the player's true raw latency.
## Use this to measure/calibrate input_offset, not to grade.
func timing_error_raw(target_beat: float) -> float:
	return live_position() - time_of_beat(target_beat)


## The whole beat nearest to the current song position. Handy for "grade the
## player's tap against whatever beat they were aiming at".
func nearest_beat() -> int:
	return int(round(song_position_in_beats))
