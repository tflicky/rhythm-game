extends Control
## Timing calibration. A click plays on every beat; the player taps along and
## the median of their tap errors becomes this computer's input_offset (the
## keyboard + audio delay the game can't see), saved via Settings.
##
## Shown automatically on first launch (see main_menu.gd) and from the menu.
## After TAPS_NEEDED taps the clicks stop and a result panel offers
## Continue (save, go to the menu) or Retry.
##   Space / click  tap     Enter  continue     R  retry     Esc  skip / back

const TAPS_NEEDED := 10
const COUNT_IN := 4          ## beats before taps count
const BEATS := 64            ## click track length; restarts if it ever ends
const RANGE := 0.25          ## seconds either side shown on the tap strip
const UNEVEN := 0.06         ## taps spread (IQR) above this -> suggest a retry
const BG := Color(0.99, 0.93, 0.8)
const INK := Color(0.2, 0.14, 0.12)

var _audio: AudioStreamPlayer
var _taps: Array[float] = []   ## raw tap errors, seconds (+ve = late)
var _done := false             ## result panel showing
var _result := 0.0
var _font: Font
var _panel: Control
var _early_at := -10000         ## ticks (ms) of the last tap made during the count-in


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
	_build_panel()
	_start()


func _exit_tree() -> void:
	Conductor.song_finished.disconnect(_on_track_finished)
	Conductor.stop()
	Conductor.stream_player = null


func _start() -> void:
	_taps.clear()
	_done = false
	_panel.visible = false
	Conductor.play()


func _finish() -> void:
	_done = true
	_result = _median(_taps)
	Conductor.stop()
	var msg: Label = _panel.get_node("Msg")
	var note: Label = _panel.get_node("Note")
	msg.text = "Your timing offset: %+d ms" % roundi(_result * 1000.0)
	note.text = "Your taps were a bit uneven -- a retry may be more accurate." \
		if _spread() > UNEVEN else "Nice and steady!"
	_panel.visible = true
	# a beat of grace so a leftover tap or click doesn't hit a button
	_set_buttons_enabled(false)
	get_tree().create_timer(0.6).timeout.connect(_set_buttons_enabled.bind(true))


func _set_buttons_enabled(on: bool) -> void:
	for b in _panel.get_node("Buttons").get_children():
		b.disabled = not on


func _continue() -> void:
	Settings.set_input_offset(_result)
	get_tree().change_scene_to_file("res://MainMenu.tscn")


func _on_track_finished() -> void:
	if not _done:
		Conductor.play()


func _process(_dt: float) -> void:
	queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if not _done:
		var tapped: bool = (e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_SPACE) \
			or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
		if tapped:
			_tap()
			return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				if _done and not _panel.get_node("Buttons/Continue").disabled:
					_continue()
			KEY_R:
				if _done and not _panel.get_node("Buttons/Retry").disabled:
					_start()
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://MainMenu.tscn")   # skip, nothing saved


func _tap() -> void:
	var b := Conductor.nearest_beat()
	if b < COUNT_IN:
		_early_at = Time.get_ticks_msec()   # shows "not yet"
		return
	var err := Conductor.timing_error_raw(float(b))   # vs the beat on the audio clock
	if absf(err) > Conductor.seconds_per_beat * 0.45:
		return   # nowhere near a beat -- a stray press
	_taps.append(err)
	if _taps.size() >= TAPS_NEEDED:
		_finish()


func _median(v: Array[float]) -> float:
	var s := v.duplicate()
	s.sort()
	var n := s.size()
	return s[n / 2] if n % 2 == 1 else (s[n / 2 - 1] + s[n / 2]) * 0.5


## Interquartile range of the taps -- how consistent they were, ignoring one-off flubs.
func _spread() -> float:
	var s := _taps.duplicate()
	s.sort()
	var n := s.size()
	return s[(3 * n) / 4] - s[n / 4]


# --- drawing -----------------------------------------------------------------

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), BG)
	var cx := vp.x * 0.5
	_text("TIMING CALIBRATION", Vector2(0, 90), 48, INK, vp.x)
	if _done:
		_draw_strip(cx, 250.0)
		return
	_text("Listen to the clicks and tap SPACE on every click.", Vector2(0, 150), 24, INK, vp.x)
	_text("Don't watch the screen -- go by sound.", Vector2(0, 182), 20, Color(INK, 0.7), vp.x)

	var beats := Conductor.song_position_in_beats
	var pulse := clampf(1.0 - fposmod(beats, 1.0) * 4.0, 0.0, 1.0)
	var counting := beats < COUNT_IN - 0.5   # taps count from the click after "4"
	if counting:
		# big 1-2-3-4, clearly a lead-in: just listen
		var n := clampi(int(floor(beats)) + 1, 1, COUNT_IN) if beats >= 0.0 else 1
		_text(str(n), Vector2(0, 330), int(96 + 24 * pulse), Color(0.85, 0.42, 0.2), vp.x)
		_text("Get ready -- just listen", Vector2(0, 385), 26, INK, vp.x)
		_text("Start tapping on the click after 4", Vector2(0, 420), 20, Color(INK, 0.7), vp.x)
		if Time.get_ticks_msec() - _early_at < 700:
			_text("Not yet -- wait for the count!", Vector2(0, 490), 24, Color(0.75, 0.25, 0.2), vp.x)
	else:
		draw_circle(Vector2(cx, 250), 18.0 + 8.0 * pulse, Color(0.85, 0.42, 0.2, 0.35 + 0.65 * pulse))
		_text("Now tap on every click!", Vector2(0, 320), 34, Color(0.25, 0.5, 0.2), vp.x)
		_draw_strip(cx, 400.0)
		_text("Taps: %d / %d" % [_taps.size(), TAPS_NEEDED], Vector2(0, 480), 26, INK, vp.x)
	_text("Esc  skip for now", Vector2(0, 610), 16, Color(INK, 0.5), vp.x)


## Centre line = on the beat; dots left are early, right are late.
func _draw_strip(cx: float, y: float) -> void:
	var half := 360.0
	draw_line(Vector2(cx - half, y), Vector2(cx + half, y), Color(INK, 0.3), 4.0)
	draw_line(Vector2(cx, y - 26), Vector2(cx, y + 26), INK, 3.0)
	_text("early", Vector2(cx - half - 90, y + 8), 18, Color(INK, 0.6), 80)
	_text("late", Vector2(cx + half + 10, y + 8), 18, Color(INK, 0.6), 80)
	for i in _taps.size():
		var x := cx + clampf(_taps[i] / RANGE, -1.0, 1.0) * half
		var newest := i == _taps.size() - 1 and not _done
		draw_circle(Vector2(x, y), 9.0 if newest else 6.0, Color(0.85, 0.42, 0.2, 1.0 if newest else 0.5))


func _text(s: String, pos: Vector2, size: int, col: Color, width: float) -> void:
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_CENTER, width, size, col)


## Result panel: offset, a steadiness note, Continue / Retry.
func _build_panel() -> void:
	_panel = VBoxContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.position.y += 90
	_panel.add_theme_constant_override("separation", 18)
	add_child(_panel)

	for spec in [["Msg", 36, INK], ["Note", 20, Color(INK, 0.7)]]:
		var l := Label.new()
		l.name = spec[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", spec[1])
		l.add_theme_color_override("font_color", spec[2])
		_panel.add_child(l)

	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	_panel.add_child(row)
	row.add_child(_button("Continue", Color(0.36, 0.62, 0.32), _continue))
	row.add_child(_button("Retry", Color(0.42, 0.5, 0.62), _start))

	var keys := Label.new()
	keys.text = "Enter  continue   -   R  retry"
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.add_theme_font_size_override("font_size", 16)
	keys.add_theme_color_override("font_color", Color(INK, 0.5))
	_panel.add_child(keys)


func _button(text: String, color: Color, action: Callable) -> Button:
	var b := Button.new()
	b.name = text
	b.text = text
	b.custom_minimum_size = Vector2(220, 64)
	b.focus_mode = Control.FOCUS_NONE   # mouse only; Enter / R are handled in _unhandled_input, and Space must never press it
	b.add_theme_font_size_override("font_size", 26)
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_stylebox_override("normal", _box(color))
	b.add_theme_stylebox_override("hover", _box(color.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", _box(color.darkened(0.15)))
	b.add_theme_stylebox_override("disabled", _box(color.darkened(0.1)))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))
	b.pressed.connect(action)
	return b


func _box(fill: Color, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(18)
	s.set_border_width_all(4 if border.a > 0.0 else 0)
	s.border_color = border
	return s


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
