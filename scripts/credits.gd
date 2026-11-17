extends Control
## Credits roll: the cast scrolls up the screen, one drawing at a time, each
## bobbing to the beat. Opened from the Credits button on the main menu.
##   Hold Space / click / touch to scroll faster.  Esc goes back to the menu.
##   When the last line has scrolled past, it goes back to the menu by itself.
##
## Edit CAST to change who's in it, their names, sizes or order.
## Edit MADE_BY for the lines after the cast.

## Each entry: name (the line under the drawing), layers (drawn on top of each
## other, same size, e.g. the bear + his arm), height (px on screen).
const CAST := [
	{"name": "Monkey", "layers": ["res://art/monkey/monkey_idle.png"], "height": 300},
	{"name": "Bonkey", "layers": ["res://art/monkey/monkey_twist_1.png"], "height": 300},
	{"name": "Surfkey", "layers": ["res://art/monkey/monkey_surfing.png"], "height": 260},
	{"name": "Squirrel", "layers": ["res://art/grilling/critters/squirrel.png"], "height": 200},
	{"name": "Dave", "layers": ["res://art/grilling/critters/bird.png"], "height": 150},
	{"name": "Raccoon", "layers": ["res://art/grilling/critters/raccoon.png"], "height": 220},
	{"name": "Bear", "layers": ["res://art/grilling/critters/bear.png",
		"res://art/grilling/critters/bear_arm.png"], "height": 300},
	{"name": "Gnome", "layers": ["res://art/wizard/gnome_0.png"], "height": 240},
]
## Lines after the cast. "" = a blank gap.
const MADE_BY := ["", "Made by", "Tommy Flick", "", "", "Thanks for playing!"]

const SCROLL_SPEED := 70.0      ## px per second
const FAST := 5.0               ## ...times this while held
const GAP := 90.0               ## space between cast members
const MAX_W := 620.0            ## wide drawings (the surfer) are shrunk to fit this
const MUSIC := "res://audio/music/menu"   ## same song as the menu, if there is one
const BPM := 120.0
const BG_TOP := Color(1.0, 0.95, 0.84)
const BG_BOTTOM := Color(0.98, 0.84, 0.68)
const INK := Color(0.2, 0.14, 0.12)

var _roll: Control               ## everything that scrolls
var _pics: Array[Control] = []   ## the drawings, for the bob
var _roll_h := 0.0
var _t := 0.0
var _leaving := false
var _music: AudioStreamPlayer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := Control.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.draw.connect(_draw_bg.bind(bg))
	add_child(bg)

	_roll = Control.new()
	_roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_roll)

	var w := get_viewport_rect().size.x
	var y := 0.0
	y = _add_label("CREDITS", 64, y, w) + GAP
	for member in CAST:
		y = _add_member(member, y, w) + GAP
	for line in MADE_BY:
		y = _add_label(line, 34 if line != "" else 20, y, w) + 10
	_roll_h = y
	_roll.position.y = get_viewport_rect().size.y   # starts just below the screen

	var hint := Label.new()
	hint.text = "hold SPACE to speed up  -  Esc to go back"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", INK.lightened(0.5))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position -= Vector2(12, 8)
	add_child(hint)

	_music = AudioStreamPlayer.new()
	_music.volume_db = -6.0
	add_child(_music)
	for ext in ["wav", "ogg", "mp3"]:
		if ResourceLoader.exists("%s.%s" % [MUSIC, ext]):
			_music.stream = load("%s.%s" % [MUSIC, ext])
			_music.finished.connect(_music.play)
			_music.play()
			break


## A centred line of text at y. Returns the y below it.
func _add_label(text: String, font_size: int, y: float, w: float) -> float:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", INK)
	l.size = Vector2(w, font_size * 1.4)
	l.position = Vector2(0, y)
	_roll.add_child(l)
	return y + l.size.y


## A cast member: their drawing (layers stacked), their name under it.
func _add_member(member: Dictionary, y: float, w: float) -> float:
	var first: String = member["layers"][0]
	if not ResourceLoader.exists(first):
		return _add_label(member["name"], 34, y, w)
	var tex: Texture2D = load(first)
	var aspect := float(tex.get_width()) / tex.get_height()
	var sz := Vector2(member["height"] * aspect, member["height"])
	if sz.x > MAX_W:
		sz *= MAX_W / sz.x
	var pic := Control.new()
	pic.size = sz
	pic.pivot_offset = Vector2(sz.x / 2.0, sz.y)     # bob from the feet
	pic.position = Vector2((w - sz.x) / 2.0, y)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for path in member["layers"]:
		if not ResourceLoader.exists(path):
			continue
		var t := TextureRect.new()
		t.texture = load(path)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.size = sz
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.add_child(t)
	_roll.add_child(pic)
	_pics.append(pic)
	return _add_label(member["name"], 34, y + sz.y + 12, w)


func _process(dt: float) -> void:
	_t += dt
	var held := Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_roll.position.y -= SCROLL_SPEED * (FAST if held else 1.0) * dt
	_roll.size.x = size.x

	# a little squash-and-hop on every beat, each one a bit behind the one before
	var beat := _t * BPM / 60.0
	if _music and _music.playing:
		beat = (_music.get_playback_position() + AudioServer.get_time_since_last_mix()
			- AudioServer.get_output_latency()) * BPM / 60.0
	for i in _pics.size():
		var p := fposmod(beat - i * 0.25, 1.0)
		var hit := pow(1.0 - p, 3.0)
		_pics[i].scale = Vector2(1.0 + 0.04 * hit, 1.0 - 0.04 * hit)
		_pics[i].rotation_degrees = 2.0 * sin(PI * (beat - i * 0.25) * 0.5)

	if _roll.position.y + _roll_h < 0.0:
		_back()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		_back()


func _back() -> void:
	if _leaving:
		return
	_leaving = true
	Transition.go("res://MainMenu.tscn")


func _draw_bg(bg: Control) -> void:
	var sz := bg.size
	var steps := 24
	for i in steps:
		var y0 := sz.y * i / steps
		var y1 := sz.y * (i + 1) / steps
		bg.draw_rect(Rect2(0, y0, sz.x, y1 - y0 + 1), BG_TOP.lerp(BG_BOTTOM, (i + 0.5) / steps))
