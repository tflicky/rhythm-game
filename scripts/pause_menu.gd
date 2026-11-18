class_name PauseMenu
extends CanvasLayer
## Esc in a level: everything freezes (the music too) and this asks
## Continue / Retry / Quit. Continue counts you back in -- 3, 2, 1, GO! on the
## beat -- and the song comes back on GO!, from the start of the beat it was
## paused in.
##
## A level hooks it up with one line in _ready:
##     _pause = PauseMenu.attach(self, _restart)
## and calls _pause.open() on Esc (it quits to the menu itself on the results screen).

const INK := Color(0.2, 0.14, 0.12)
const CREAM := Color(1, 0.97, 0.88)
const COUNT := 3                       ## beats counted in when you continue
const MENU_SCENE := "res://MainMenu.tscn"

var _retry: Callable
var _root: Control
var _buttons: Array[Button] = []
var _count_label: Label
var _tick: AudioStreamPlayer
var _ticks_at: Array = []              ## ms (ticks) of each count beat still to come
var _resume_at := -1                   ## ms when the music comes back; -1 = not counting
var _go_at := -1                       ## ms "GO!" goes up -- the music comes back then; -1 = not showing
var _rewind := 0.0                     ## seconds the song backs up on GO!, to the start of the beat it paused in
var _pause_button: Button              ## the "II" in the corner, for phones (no Esc key)


## Add a pause menu to `level`. `retry` restarts the level.
static func attach(level: Node, retry: Callable) -> PauseMenu:
	var p := PauseMenu.new()
	p._retry = retry
	level.add_child(p)
	return p


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps working while the level is paused
	layer = 50
	_build()
	_root.visible = false
	_count_label.visible = false
	_tick = AudioStreamPlayer.new()
	_tick.volume_db = -6.0
	add_child(_tick)


func is_busy() -> bool:
	return _root.visible or _resume_at >= 0


## Freeze the level and show the menu.
func open() -> void:
	if _root.visible:
		return
	_pause_button.visible = false
	_resume_at = -1
	_go_at = -1
	_ticks_at.clear()
	_count_label.visible = false
	_count_label.modulate.a = 1.0
	get_tree().paused = true
	_root.visible = true
	_buttons[0].grab_focus()


func _continue() -> void:
	_root.visible = false
	_pause_button.visible = true
	if not Conductor.playing or Conductor.seconds_per_beat <= 0.0:
		get_tree().paused = false            # nothing playing (a card): just carry on
		return
	# Count in on the beat: 3, 2, 1, then GO! -- and the song comes back right on
	# GO!. It stopped `f` of the way through a beat, so it backs up that little
	# bit to the start of that beat: the beat you hear on GO! is a real one.
	var spb := Conductor.seconds_per_beat
	var f := fposmod((Conductor.song_position - Conductor.first_beat_offset) / spb, 1.0)
	_rewind = f * spb
	var now := Time.get_ticks_msec()
	var first := 150.0                    # ms before the first count, so it doesn't snap
	_go_at = now + int(first + COUNT * spb * 1000.0)
	_resume_at = _go_at
	_ticks_at.clear()
	for i in COUNT:
		_ticks_at.append(now + int(first + i * spb * 1000.0))
	if _tick.stream == null:
		_tick.stream = ClickTrack.make(Conductor.bpm, 1, 4, 0.0)


func _do_retry() -> void:
	_close()
	_retry.call()


func _quit() -> void:
	_close()
	get_tree().change_scene_to_file(MENU_SCENE)


func _close() -> void:
	_root.visible = false
	_pause_button.visible = true
	_count_label.visible = false
	_resume_at = -1
	_go_at = -1
	_ticks_at.clear()
	get_tree().paused = false


func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	# GO!: back up to the start of the beat we paused in, and let the music go
	if _resume_at >= 0 and now >= _resume_at:
		_resume_at = -1
		get_tree().paused = false
		var sp := Conductor.stream_player
		if is_instance_valid(sp) and _rewind > 0.0:
			sp.seek(maxf(sp.get_playback_position() - _rewind, 0.0))
			Conductor.song_position -= _rewind
			Conductor.song_position_in_beats = (Conductor.song_position - Conductor.first_beat_offset) / Conductor.seconds_per_beat
	if _go_at < 0:
		return
	var spb_ms := Conductor.seconds_per_beat * 1000.0
	if now >= _go_at:
		var kg := (now - _go_at) / spb_ms    # beats since GO!
		if kg >= 1.0:
			_count_label.visible = false
			_count_label.modulate.a = 1.0
			_count_label.set_meta("last", -1)
			_go_at = -1
			return
		_count_label.visible = true
		_count_label.text = "GO!"
		_count_label.scale = Vector2.ONE * (1.0 + 0.4 * exp(-kg * 7.0))
		_count_label.modulate.a = 1.0 - clampf((kg - 0.5) / 0.5, 0.0, 1.0)   # fades over its 2nd half-beat
		return
	# show 3, 2, 1 -- each from its own beat, with a tick
	var shown := -1
	for i in COUNT:
		if now >= _ticks_at[i]:
			shown = i
	if shown >= 0:
		var k := (now - int(_ticks_at[shown])) / spb_ms
		_count_label.visible = true
		_count_label.text = str(COUNT - shown)
		_count_label.scale = Vector2.ONE * (1.0 + 0.4 * exp(-k * 7.0))
		if _count_label.get_meta("last", -1) != shown:
			_count_label.set_meta("last", shown)
			_tick.play()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE):
		return
	if _root.visible:                     # Esc again = continue
		_continue()
		get_viewport().set_input_as_handled()
	elif _resume_at >= 0:                 # Esc during the count-in: back to the menu
		_resume_at = -1
		_go_at = -1
		_count_label.visible = false
		_count_label.set_meta("last", -1)
		_root.visible = true
		_buttons[0].grab_focus()
		get_viewport().set_input_as_handled()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CREAM
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(4)
	sb.border_color = INK
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", INK)
	col.add_child(title)
	for item in [["Continue", Color(0.36, 0.62, 0.32), _continue],
			["Retry", Color(0.85, 0.55, 0.2), _do_retry],
			["Quit", Color(0.75, 0.3, 0.25), _quit]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(300, 62)
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_focus_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		for state in ["normal", "hover", "pressed", "focus"]:
			var s := StyleBoxFlat.new()
			s.bg_color = (item[1] as Color).lightened(0.12) if state == "hover" else item[1]
			s.set_corner_radius_all(14)
			if state == "focus":        # the selected one gets a thick dark ring
				s.draw_center = false
				s.set_border_width_all(5)
				s.border_color = INK
				s.set_expand_margin_all(3)
			b.add_theme_stylebox_override(state, s)
		b.pressed.connect(item[2])
		col.add_child(b)
		_buttons.append(b)

	# a pause button in the top-left corner: phones have no Esc key
	_pause_button = Button.new()
	_pause_button.text = "II"
	_pause_button.focus_mode = Control.FOCUS_NONE   # SPACE must never press it
	_pause_button.position = Vector2(14, 14)
	_pause_button.custom_minimum_size = Vector2(56, 56)
	_pause_button.add_theme_font_size_override("font_size", 24)
	for state in ["normal", "hover", "pressed"]:
		var ps := StyleBoxFlat.new()
		ps.bg_color = Color(CREAM, 0.75 if state == "normal" else 0.95)
		ps.set_corner_radius_all(12)
		ps.set_border_width_all(3)
		ps.border_color = Color(INK, 0.7)
		_pause_button.add_theme_stylebox_override(state, ps)
	_pause_button.add_theme_color_override("font_color", INK)
	_pause_button.add_theme_color_override("font_hover_color", INK)
	_pause_button.add_theme_color_override("font_pressed_color", INK)
	_pause_button.pressed.connect(open)
	add_child(_pause_button)

	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 120)
	_count_label.add_theme_color_override("font_color", Color(1, 0.88, 0.3))
	_count_label.add_theme_color_override("font_outline_color", INK)
	_count_label.add_theme_constant_override("outline_size", 18)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.size = Vector2(300, 200)
	_count_label.pivot_offset = _count_label.size / 2.0
	_count_label.position = Vector2(1152, 648) / 2.0 - _count_label.size / 2.0
	add_child(_count_label)
