class_name TutorialUI
## The practice-shot boxes, drawn the same way and in the same spot in every
## level:
##   - a caption panel: "Practice 1/2" / "Try again!" + a hint
##   - a press box saying what to press -- the key on a computer (SPACE, or the
##     level's own key like A / D), TAP on a phone or tablet -- with a box of the
##     same shape closing in on it that wraps it exactly when you should press
##     (it shows up 2 beats ahead), pulsing while the game waits for you
##   - skipping practice: on a computer a small key hint ("S: skip"); on a phone
##     a Skip button there instead (add_skip_button)
## Each level calls these from its own drawing.
##
## Where they go: press F3 in any level to drag them around (scripts/tutorial_editor.gd);
## F3 again saves the new spots into the three lines under LAYOUT below.

const VP := Vector2(1152, 648)
const INK := Color(0.2, 0.14, 0.12)
const HOT := Color(0.95, 0.55, 0.15)       ## TAP box border + square (orange)
const HINT := Color(0.6, 0.32, 0.08)       ## the caption's second line
const CAPTION_SIZE := Vector2(376, 112)
const TAP_HALF := Vector2(48, 28)          ## smallest half-size (longer words make it wider)
const SKIP_SIZE := Vector2(150, 54)        ## the phone's Skip button
const BORDER := 4.0                        ## the press box's border width -- the closing box lands right on it
const FAR := 3.0                           ## how many times bigger the closing box starts
const SELF_PATH := "res://scripts/tutorial_ui.gd"

# LAYOUT -- written by the F3 drag mode; you can also type numbers here.
static var caption_pos := Vector2(752, 24)   ## the caption panel's top-left corner
static var tap_at := Vector2(870, 390)       ## the press box's middle (Wizard's ICE box mirrors it on the left)
static var skip_at := Vector2(1136, 632)     ## bottom-right corner of the skip hint / Skip button

## Set to true / false to test the phone / computer look; null = detect it.
static var force_touch: Variant = null

static var _panel: StyleBoxFlat
static var _skip_buttons: Array = []


static func _panel_style() -> StyleBoxFlat:
	if _panel == null:
		_panel = StyleBoxFlat.new()
		_panel.bg_color = Color(1, 0.97, 0.88, 0.92)
		_panel.set_corner_radius_all(18)
		_panel.set_border_width_all(4)
		_panel.border_color = INK
	return _panel


static func caption_rect() -> Rect2:
	return Rect2(caption_pos, CAPTION_SIZE)


static func caption(ci: CanvasItem, head: String, sub: String, sub_col := HINT) -> void:
	var font := ThemeDB.fallback_font
	var box := caption_rect()
	ci.draw_style_box(_panel_style(), box)
	ci.draw_string(font, Vector2(box.position.x, box.position.y + 46), head, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 32, INK)
	ci.draw_string(font, Vector2(box.position.x, box.position.y + 86), sub, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 22, sub_col)


## The computer's skip hint, its bottom-right at `skip_at`. On a phone nothing is
## drawn: the Skip button (add_skip_button) is there instead.
static func skip_hint(ci: CanvasItem, text := "S: skip", col := Color(INK, 0.45)) -> void:
	if is_touch():
		return
	ci.draw_string(ThemeDB.fallback_font, skip_at - Vector2(200, 0), text, HORIZONTAL_ALIGNMENT_RIGHT, 200, 14, col)


## Playing on a phone or tablet (the app, or the web build in a phone browser)?
static func is_touch() -> bool:
	if force_touch != null:
		return force_touch
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


## What the press box says: `key` on a computer, TAP on a phone.
static func label(key: String) -> String:
	return "TAP" if is_touch() else key


static func _half(text: String) -> Vector2:
	var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	return Vector2(maxf(TAP_HALF.x, w / 2.0 + 18.0), TAP_HALF.y)


## The press box (faded when nothing is coming), centred on `c` -- `tap_at` if
## not given. `key` = the key on a computer; a phone shows TAP.
static func tap_box(ci: CanvasItem, live: bool, c := Vector2.INF, col := HOT, key := "SPACE") -> void:
	if c == Vector2.INF:
		c = tap_at
	var text := label(key)
	var half := _half(text)
	var cap := Rect2(c - half, half * 2.0)
	ci.draw_rect(cap.grow(BORDER), col if live else Color(col, 0.4))
	ci.draw_rect(cap, Color(1, 0.97, 0.88, 1.0 if live else 0.5))
	ci.draw_string(ThemeDB.fallback_font, Vector2(cap.position.x, cap.position.y + 39), text,
		HORIZONTAL_ALIGNMENT_CENTER, cap.size.x, 30, Color(INK, 1.0 if live else 0.5))


## The box closing in on the press box (same shape). `left` = seconds until the
## press is due. `frozen` = the game is waiting for your press: it pulses around it.
static func square(ci: CanvasItem, left: float, frozen: bool, late_ok: float,
		c := Vector2.INF, col := HOT, key := "SPACE") -> void:
	if c == Vector2.INF:
		c = tap_at
	# the middle of the press box's border: a BORDER-wide line here covers it exactly
	var hug := _half(label(key)) + Vector2.ONE * (BORDER * 0.5)
	if frozen:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 2.0)
		_rect(ci, c, hug + Vector2(6, 6) * pulse, col, BORDER)
		return
	var lead := 2.0 * Conductor.seconds_per_beat
	if left > lead or left < -late_ok:
		return
	var k := clampf(left / lead, 0.0, 1.0)
	_rect(ci, c, hug * lerpf(1.0, FAR, k), Color(col, 1.0 - 0.6 * k), BORDER)


static func _rect(ci: CanvasItem, c: Vector2, half: Vector2, col: Color, width: float) -> void:
	ci.draw_rect(Rect2(c - half, half * 2.0), col, false, width)


## Phone only: a "Skip" button, its bottom-right at `skip_at`, that calls `on_skip`.
## Returns it (null on a computer) -- the level shows it only during practice
## (`button.visible = ...`). Being a real button, a tap on it never counts as a press.
static func add_skip_button(parent: Node, on_skip: Callable) -> Button:
	if not is_touch():
		return null
	var layer := CanvasLayer.new()
	layer.layer = 20
	parent.add_child(layer)
	var b := Button.new()
	b.text = "Skip  >>"
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 24)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, INK)
	var sb := _panel_style().duplicate() as StyleBoxFlat
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	for st in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	var down := sb.duplicate() as StyleBoxFlat
	down.bg_color = Color(0.92, 0.86, 0.72)
	b.add_theme_stylebox_override("pressed", down)
	b.size = SKIP_SIZE
	b.position = skip_at - SKIP_SIZE
	b.pressed.connect(on_skip)
	layer.add_child(b)
	_skip_buttons.append(b)
	return b


## Move any Skip buttons to `skip_at` (after dragging it).
static func place_skip_buttons() -> void:
	_skip_buttons = _skip_buttons.filter(func(b): return is_instance_valid(b))
	for b: Button in _skip_buttons:
		b.position = skip_at - SKIP_SIZE


## Write the current spots into the LAYOUT lines of this script, so they stick.
## Only works when running from the project (not an exported game).
static func save_layout() -> bool:
	if OS.has_feature("template"):
		return false
	var f := FileAccess.open(SELF_PATH, FileAccess.READ)
	if f == null:
		return false
	var lines := f.get_as_text().split("\n")
	f.close()
	var vals := {"caption_pos": caption_pos, "tap_at": tap_at, "skip_at": skip_at}
	var n := 0
	for i in lines.size():
		for key: String in vals:
			var head := "static var %s := Vector2(" % key
			if lines[i].begins_with(head):
				var v: Vector2 = vals[key]
				var rest := lines[i].substr(lines[i].find(")") + 1)    # keep the comment
				lines[i] = "%s%d, %d)%s" % [head, roundi(v.x), roundi(v.y), rest]
				n += 1
	if n != vals.size():
		return false
	f = FileAccess.open(SELF_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("\n".join(lines))
	f.close()
	return true
