extends CanvasLayer
## Drag mode for the practice boxes (an autoload, "TutorialEditor").
##   F3            turn it on: each box gets a dashed outline with its name
##   drag (mouse)  move a box -- the game keeps running, so you see the real thing
##   F3 again      save: the spots are written into scripts/tutorial_ui.gd (LAYOUT)
## The spots are shared by every level. Clicks while it's on don't reach the game.

const PINK := Color(1.0, 0.2, 0.6)

var _on := false
var _drag := ""                     ## which box is being dragged ("" = none)
var _grab := Vector2.ZERO           ## mouse offset from that box's anchor
var _toast := ""
var _toast_ms := -100000
var _overlay: Control


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func _process(_dt: float) -> void:
	if _on or Time.get_ticks_msec() - _toast_ms < 2500:
		_overlay.queue_redraw()
	elif _toast != "":
		_toast = ""
		_overlay.queue_redraw()


## name -> the box's rect on screen (for grabbing and outlining).
func _boxes() -> Dictionary:
	var tap_half := Vector2(70, 38)
	return {
		"caption": TutorialUI.caption_rect(),
		"press box": Rect2(TutorialUI.tap_at - tap_half, tap_half * 2.0),
		"skip": Rect2(TutorialUI.skip_at - TutorialUI.SKIP_SIZE, TutorialUI.SKIP_SIZE),
	}


func _anchor(name: String) -> Vector2:
	match name:
		"caption": return TutorialUI.caption_pos
		"press box": return TutorialUI.tap_at
		_: return TutorialUI.skip_at


func _set_anchor(name: String, p: Vector2) -> void:
	var r: Rect2 = _boxes()[name]
	var off := p - _anchor(name)                     # keep the whole box on screen
	r.position += off
	var fix := Vector2(
		clampf(r.position.x, 0.0, TutorialUI.VP.x - r.size.x) - r.position.x,
		clampf(r.position.y, 0.0, TutorialUI.VP.y - r.size.y) - r.position.y)
	p += fix
	match name:
		"caption": TutorialUI.caption_pos = p.round()
		"press box": TutorialUI.tap_at = p.round()
		_:
			TutorialUI.skip_at = p.round()
			TutorialUI.place_skip_buttons()


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F3:
		_toggle()
		get_viewport().set_input_as_handled()
		return
	if not _on:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			var boxes := _boxes()
			for name: String in ["skip", "press box", "caption"]:    # small ones first
				if (boxes[name] as Rect2).has_point(e.position):
					_drag = name
					_grab = e.position - _anchor(name)
					break
		else:
			_drag = ""
		get_viewport().set_input_as_handled()
	elif e is InputEventMouseMotion:
		if _drag != "":
			_set_anchor(_drag, e.position - _grab)
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenTouch or e is InputEventScreenDrag:
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	_on = not _on
	_drag = ""
	if not _on:
		_toast = "Saved the box spots" if TutorialUI.save_layout() \
			else "Couldn't save (only works when running the project)"
		_toast_ms = Time.get_ticks_msec()
	_overlay.queue_redraw()


func _draw_overlay() -> void:
	var font := ThemeDB.fallback_font
	var o := _overlay
	if _on:
		var boxes := _boxes()
		for name: String in boxes:
			var r: Rect2 = boxes[name]
			var col := PINK if name == _drag else Color(PINK, 0.75)
			o.draw_rect(r, Color(PINK, 0.08 if name != _drag else 0.18))
			var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
			for i in 4:
				o.draw_dashed_line(c[i], c[(i + 1) % 4], col, 3.0, 10.0)
			o.draw_string_outline(font, r.position + Vector2(4, -6), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 6, Color.WHITE)
			o.draw_string(font, r.position + Vector2(4, -6), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, PINK.darkened(0.3))
		# the Wizard's ICE box sits at the mirror spot on the left
		var tr: Rect2 = boxes["press box"]
		var mr := Rect2(Vector2(TutorialUI.VP.x - tr.end.x, tr.position.y), tr.size)
		o.draw_rect(mr, Color(PINK, 0.35), false, 2.0)
		o.draw_string(font, mr.position + Vector2(4, -6), "(Wizard ICE: mirrors it)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(PINK, 0.6))
		_banner(o, font, "LAYOUT MODE  -  drag the boxes  -  F3 to save")
	elif _toast != "":
		_banner(o, font, _toast)


func _banner(o: Control, font: Font, text: String) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 40.0
	var r := Rect2(TutorialUI.VP.x / 2.0 - w / 2.0, TutorialUI.VP.y / 2.0 - 22.0, w, 44)
	r.position.y = TutorialUI.VP.y - 110.0
	o.draw_rect(r, Color(0.1, 0.05, 0.1, 0.85))
	o.draw_string(font, Vector2(r.position.x, r.position.y + 29), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, Color.WHITE)
