extends Control
## Sync calibration overlay. Delete (or hide) this once timing is dialled in.
##
## On every Conductor beat it plays a click and flashes the screen, so you can
## hear/see the beat grid against the actual music. If the click drifts or sits
## off the groove, the BPM or the offset is wrong -- fix those numbers, not code.
##
## Keys:
##   T              register a tap; prints raw + compensated error vs nearest beat
##   C              set input_offset = median of recent taps (input calibration)
##   Up / Down       first_beat_offset  +/- 5 ms   (moves the whole grid vs audio)
##   ] / [           calibration_offset +/- 5 ms   (audio output latency trim)
##   . / ,           video_offset       +/- 5 ms   (display lag: draw visuals ahead)
##   M               toggle the metronome click   (default off during play)
## (R restarts the level -- handled by rhythm.gd, not here)

const NUDGE := 0.005
const TAP_HISTORY := 16

var _click_player: AudioStreamPlayer
var _metronome := false
var _label: Label
var _flash: ColorRect
var _flash_energy := 0.0
var _last_tap_err := 0.0
var _taps: Array[float] = []  ## recent RAW tap errors, seconds


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)

	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)

	_click_player = AudioStreamPlayer.new()
	_click_player.stream = _make_click(2000.0, 0.030)
	_click_player.bus = &"Master"
	add_child(_click_player)

	Conductor.beat.connect(_on_beat)
	set_process(true)


func _on_beat(index: int) -> void:
	_flash_energy = 1.0
	if _metronome:
		var accent: bool = index % Conductor.beats_per_measure == 0
		_click_player.pitch_scale = 1.5 if accent else 1.0
		_click_player.play()


func _process(delta: float) -> void:
	_flash_energy = maxf(0.0, _flash_energy - delta * 8.0)
	_flash.color.a = _flash_energy * 0.10

	_label.text = "\n".join([
		"song %.3fs    beat %.2f    nearest %d" % [
			Conductor.song_position, Conductor.song_position_in_beats, Conductor.nearest_beat()],
		"bpm %.1f    sec/beat %.4f" % [Conductor.bpm, Conductor.seconds_per_beat],
		"first_beat_offset  %+.3fs   [Up/Down]" % Conductor.first_beat_offset,
		"calibration_offset %+.3fs   [ ] / [ ]" % Conductor.calibration_offset,
		"video_offset %+.0f ms   [ . / , ]  (visuals only)" % (Conductor.video_offset * 1000.0),
		"input_offset %+.0f ms   [C] = median of %d taps" % [
			Conductor.input_offset * 1000.0, _taps.size()],
		"metronome %s    [M]" % ("ON" if _metronome else "off"),
		"last tap: raw %+.0f ms   compensated %+.0f ms   [T]" % [
			_last_tap_err * 1000.0, (_last_tap_err - Conductor.input_offset) * 1000.0],
	])


func _unhandled_input(event: InputEvent) -> void:
	# Calibration keys only while developing -- in an exported game a stray arrow
	# or bracket press would silently shift the timing.
	if not OS.is_debug_build():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_T:
			var target := float(Conductor.nearest_beat())
			_last_tap_err = Conductor.timing_error_raw(target)
			_taps.append(_last_tap_err)
			if _taps.size() > TAP_HISTORY:
				_taps.pop_front()
			print("[tap] beat %d   raw %+.1f ms   compensated %+.1f ms" % [
				int(target), _last_tap_err * 1000.0,
				(_last_tap_err - Conductor.input_offset) * 1000.0])
		KEY_C:
			if _taps.is_empty():
				print("[cal] no taps yet -- tap Space to the beat a dozen times first")
			else:
				Conductor.input_offset = _median(_taps)
				var spread: float = (_taps.max() - _taps.min()) * 1000.0
				print("[cal] input_offset = %+.1f ms  (from %d taps, spread %.0f ms)" % [
					Conductor.input_offset * 1000.0, _taps.size(), spread])
		KEY_UP:
			Conductor.first_beat_offset += NUDGE
			print("[cal] first_beat_offset = %+.3f" % Conductor.first_beat_offset)
		KEY_DOWN:
			Conductor.first_beat_offset -= NUDGE
			print("[cal] first_beat_offset = %+.3f" % Conductor.first_beat_offset)
		KEY_BRACKETRIGHT:
			Conductor.calibration_offset += NUDGE
			print("[cal] calibration_offset = %+.3f" % Conductor.calibration_offset)
		KEY_BRACKETLEFT:
			Conductor.calibration_offset -= NUDGE
			print("[cal] calibration_offset = %+.3f" % Conductor.calibration_offset)
		KEY_PERIOD:
			Conductor.video_offset += NUDGE
			print("[cal] video_offset = %+.3f  (visuals drawn earlier)" % Conductor.video_offset)
		KEY_COMMA:
			Conductor.video_offset -= NUDGE
			print("[cal] video_offset = %+.3f  (visuals drawn later)" % Conductor.video_offset)
		KEY_M:
			_metronome = not _metronome


func _median(values: Array[float]) -> float:
	var s := values.duplicate()
	s.sort()
	var n := s.size()
	if n % 2 == 1:
		return s[n / 2]
	return (s[n / 2 - 1] + s[n / 2]) * 0.5


## Short procedural sine "tick" so we don't need an audio asset for calibration.
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
