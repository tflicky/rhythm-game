extends Control
## Timing calibration. A click plays on every beat; the player taps along and
## the median of their tap errors becomes this computer's input_offset (the
## keyboard + audio delay the game can't see), saved via Settings.
##   Space / click  tap    Enter  save    Backspace  start over    Esc  back

const MIN_TAPS := 8
const KEEP_TAPS := 16
const COUNT_IN := 4          ## beats before taps count
const BEATS := 64            ## click track length; restarts when it ends
const RANGE := 0.25          ## seconds either side shown on the tap strip
const BG := Color(0.99, 0.93, 0.8)
const INK := Color(0.2, 0.14, 0.12)

var _audio: AudioStreamPlayer
var _taps: Array[float] = []   ## raw tap errors, seconds (+ve = late)
var _saved_msg := ""
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	var map: Resource = load("res://beatmaps/rhythm_monkey.tres")
	Conductor.bpm = map.bpm if map else 128.0
	Conductor.first_beat_offset = 0.0
	_audio = AudioStreamPlayer.new()
	_audio.stream = _make_click_track()
	add_child(_audio)
	Conductor.stream_player = _audio
	Conductor.song_finished.connect(_on_track_finished)
	Conductor.play()


func _exit_tree() -> void:
	Conductor.song_finished.disconnect(_on_track_finished)
	Conductor.stop()
	Conductor.stream_player = null


func _on_track_finished() -> void:
	Conductor.play()


func _process(_dt: float) -> void:
	queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	var tapped: bool = (e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_SPACE) \
		or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
	if tapped:
		_tap()
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				if _taps.size() >= MIN_TAPS:
					Settings.set_input_offset(_median())
					_saved_msg = "Saved! Your timing offset is %+d ms." % roundi(_median() * 1000.0)
			KEY_BACKSPACE:
				_taps.clear()
				_saved_msg = ""
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://MainMenu.tscn")


func _tap() -> void:
	var b := Conductor.nearest_beat()
	if b < COUNT_IN:
		return
	var err := Conductor.timing_error_raw(float(b))   # vs the beat on the audio clock
	if absf(err) > Conductor.seconds_per_beat * 0.45:
		return   # nowhere near a beat -- a stray press
	_taps.append(err)
	if _taps.size() > KEEP_TAPS:
		_taps.pop_front()
	_saved_msg = ""


func _median() -> float:
	var s := _taps.duplicate()
	s.sort()
	var n := s.size()
	return s[n / 2] if n % 2 == 1 else (s[n / 2 - 1] + s[n / 2]) * 0.5


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), BG)
	var cx := vp.x * 0.5
	_text("TIMING CALIBRATION", Vector2(0, 90), 48, INK, vp.x)
	_text("Listen to the clicks and tap SPACE exactly on each one.", Vector2(0, 150), 24, INK, vp.x)
	_text("Don't watch the screen -- go by sound.", Vector2(0, 182), 20, Color(INK, 0.7), vp.x)

	# beat light, so you can tell it's running (count-in shown as 1-2-3-4)
	var beats := Conductor.song_position_in_beats
	var phase := fposmod(beats, 1.0)
	var pulse := clampf(1.0 - phase * 4.0, 0.0, 1.0)
	draw_circle(Vector2(cx, 250), 18.0 + 8.0 * pulse, Color(0.85, 0.42, 0.2, 0.35 + 0.65 * pulse))
	if beats >= 0.0 and beats < COUNT_IN:
		_text(str(int(beats) + 1), Vector2(0, 320), 28, INK, vp.x)

	# tap strip: centre line = on the beat; left early, right late
	var y := 390.0
	var half := 360.0
	draw_line(Vector2(cx - half, y), Vector2(cx + half, y), Color(INK, 0.3), 4.0)
	draw_line(Vector2(cx, y - 26), Vector2(cx, y + 26), INK, 3.0)
	_text("early", Vector2(cx - half - 90, y + 8), 18, Color(INK, 0.6), 80)
	_text("late", Vector2(cx + half + 10, y + 8), 18, Color(INK, 0.6), 80)
	for i in _taps.size():
		var x := cx + clampf(_taps[i] / RANGE, -1.0, 1.0) * half
		var newest := i == _taps.size() - 1
		draw_circle(Vector2(x, y), 9.0 if newest else 6.0, Color(0.85, 0.42, 0.2, 1.0 if newest else 0.5))

	var saved := "Saved on this computer: %+d ms" % roundi(Settings.input_offset() * 1000.0) \
		if Settings.has_input_offset() else "Not calibrated yet on this computer"
	if _taps.size() < MIN_TAPS:
		_text("Taps: %d / %d" % [_taps.size(), MIN_TAPS], Vector2(0, 470), 26, INK, vp.x)
	else:
		_text("Your timing offset: %+d ms" % roundi(_median() * 1000.0), Vector2(0, 470), 30, INK, vp.x)
		_text("Keep tapping to refine, then press ENTER to save", Vector2(0, 506), 20, INK, vp.x)
	if _saved_msg != "":
		_text(_saved_msg, Vector2(0, 548), 24, Color(0.25, 0.5, 0.2), vp.x)
	else:
		_text(saved, Vector2(0, 548), 18, Color(INK, 0.6), vp.x)
	_text("Enter  save   -   Backspace  start over   -   Esc  back", Vector2(0, 610), 16, Color(INK, 0.5), vp.x)


func _text(s: String, pos: Vector2, size: int, col: Color, width: float) -> void:
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_CENTER, width, size, col)


## Click on every beat (accented on the bar), BEATS long, not looped -- the
## Conductor clock must never jump backwards; song_finished restarts it.
func _make_click_track() -> AudioStreamWAV:
	var rate := 44100
	var spb: float = Conductor.seconds_per_beat
	var n := int(rate * (spb * BEATS + 0.5))
	var data := PackedByteArray()
	data.resize(n * 2)
	var click_n := int(rate * 0.04)
	for b in BEATS:
		var freq := 1600.0 if b % Conductor.beats_per_measure == 0 else 1000.0
		var start := int(rate * b * spb)
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
