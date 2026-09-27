extends Node2D
## Tap-to-chart recorder. Play the song and tap where you want the cues to be.
## Taps are input-latency compensated, then saved into the beatmap's `cues` list
## (a non-empty `cues` overrides the generated pattern, so the game then plays
## exactly what you tapped).
##
## Keys:
##   Space / click   mark a cue at the current song position
##   Z               undo last mark
##   X               clear all marks
##   Q               cycle quantize:  OFF (raw)  ->  1/4  ->  1/8  ->  1/16  ->  1/2
##   S               save marks into res://beatmaps/rhythm_monkey.tres  (+ print)
##   R               restart the song (marks are kept)
##   F2              back to play mode (handled by rhythm.gd)

const VP := Vector2(1152, 648)
const SAVE_PATH := "res://beatmaps/rhythm_monkey.tres"
const Q_STEPS := [0.0, 0.25, 0.125, 0.0625, 0.5]      ## beats; 0 = raw, no snap
const Q_NAMES := ["OFF (raw)", "1/4", "1/8", "1/16", "1/2"]
const SONG_LEN := 71.3                                ## seconds, for the timeline

var _marks: Array[float] = []   ## cue positions in BEATS (input-latency compensated)
var _q := 0
var _flash_t := -10.0
var _msg := ""
var _msg_t := -10.0


func begin() -> void:
	set_process(true)
	queue_redraw()


func _process(_dt: float) -> void:
	queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_accept") \
			or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
			or (e is InputEventScreenTouch and e.pressed):
		_mark()
		return
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	match e.keycode:
		KEY_Z:
			if not _marks.is_empty():
				_marks.pop_back()
				_flash("undo")
		KEY_X:
			_marks.clear()
			_flash("cleared")
		KEY_Q:
			_q = (_q + 1) % Q_STEPS.size()
			_flash("quantize " + Q_NAMES[_q])
		KEY_S:
			_save()


func _mark() -> void:
	if not Conductor.playing:
		return
	var t: float = Conductor.live_position() - Conductor.input_offset
	_marks.append(t / Conductor.seconds_per_beat)
	_flash_t = Conductor.song_position


func _flash(text: String) -> void:
	_msg = text
	_msg_t = Conductor.song_position


## Marks snapped to the current grid, de-duped, sorted. Raw when quantize is OFF.
func _resolved() -> Array:
	var step: float = Q_STEPS[_q]
	var seen := {}
	var out: Array = []
	for b in _marks:
		var v: float = b if step <= 0.0 else roundf(b / step) * step
		var key: float = snappedf(v, 0.0001)
		if not seen.has(key):
			seen[key] = true
			out.append(v)
	out.sort()
	return out


func _save() -> void:
	var bm: Resource = load(SAVE_PATH)
	if bm == null:
		_flash("save FAILED: cannot load " + SAVE_PATH)
		return
	var cues: Array = []
	for b in _resolved():
		cues.append({"beat": b, "cue": "catch"})
	bm.set("cues", cues)
	var err := ResourceSaver.save(bm, SAVE_PATH)
	if err == OK:
		_flash("SAVED %d cues  (restart / F2 to play them)" % cues.size())
	else:
		_flash("ResourceSaver err %d -- copy the array from the console" % err)
	print("[recorder] cues = ", JSON.stringify(cues))


func _draw() -> void:
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, VP), Color(0.11, 0.13, 0.17))

	draw_string(font, Vector2(40, 64), "CHART RECORDER", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color.WHITE)
	draw_string(font, Vector2(40, 116), "song beat  %7.2f        bpm %.1f" % [
		Conductor.song_position_in_beats, Conductor.bpm], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.8, 0.85, 0.95))
	draw_string(font, Vector2(40, 154), "marks  %d        quantize  %s   [Q]" % [
		_marks.size(), Q_NAMES[_q]], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.8, 0.85, 0.95))
	draw_string(font, Vector2(40, 200), "[Space]/click mark    [Z] undo    [X] clear    [S] save    [R] restart    [F2] play",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.6, 0.65, 0.75))

	# tap flash
	if Conductor.song_position - _flash_t < 0.12:
		draw_circle(VP * 0.5, 70.0, Color(1, 1, 1, 0.85))

	# message
	if Conductor.song_position - _msg_t < 2.0 and _msg != "":
		draw_string(font, Vector2(40, 250), _msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.5, 1.0, 0.65))

	# timeline with mark ticks + playhead
	var y := 380.0
	var x0 := 40.0
	var x1 := VP.x - 40.0
	draw_line(Vector2(x0, y), Vector2(x1, y), Color(1, 1, 1, 0.25), 2.0)
	for b in _resolved():
		var t: float = b * Conductor.seconds_per_beat
		var x: float = lerpf(x0, x1, clampf(t / SONG_LEN, 0.0, 1.0))
		draw_line(Vector2(x, y - 14), Vector2(x, y + 14), Color(0.4, 0.8, 1.0), 2.0)
	var px: float = lerpf(x0, x1, clampf(Conductor.song_position / SONG_LEN, 0.0, 1.0))
	draw_line(Vector2(px, y - 24), Vector2(px, y + 24), Color(1.0, 0.8, 0.3), 3.0)

	# recent marks, numeric
	var res := _resolved()
	var tail: Array = res.slice(maxi(0, res.size() - 20))
	var line := ""
	for b in tail:
		line += "%.2f  " % b
	draw_string(font, Vector2(40, 440), line, HORIZONTAL_ALIGNMENT_LEFT, x1 - x0, 20, Color(0.7, 0.85, 1.0))
