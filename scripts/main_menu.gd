extends Control
## Level select: one big card per level, side by side. Built in code so adding a
## level is one entry in LEVELS.
##   Left/Right or mouse to pick, Enter/Space/click to play, Down for Calibrate.
##   Esc in a level comes back here.
## A level whose scene doesn't exist yet shows as "coming soon" and can't be picked.
##
## Menu song: drop your track in audio/music/ as menu.wav (or .ogg / .mp3) and set
## MENU_BPM to its tempo. The cards bounce to its beat. No file = no music; the
## cards still bounce, to MENU_BPM.

const LEVELS := [
	{"title": "Monkey Business", "scene": "res://Rhythm.tscn",
		"color": Color(0.36, 0.62, 0.32),
		# icon layers, back to front: texture, top-left and size inside the ICON_SIZE box,
		# optional rot in degrees (spins around the layer's own centre)
		"icon": [
			# just the banana bunch
			{"tex": "res://art/monkey/banana.png", "pos": Vector2(0, 0), "size": Vector2(110, 110)},
		]},
	{"title": "Grill Master","scene": "res://Grill.tscn",
		"color": Color(0.85, 0.42, 0.2),
		"icon": [
			{"tex": "res://art/grilling/icon/tongs.png", "pos": Vector2(-2, 0), "size": Vector2(74, 74), "rot": -10.0},
			{"tex": "res://art/grilling/icon/grill.png", "pos": Vector2(30, 20), "size": Vector2(94, 94), "rot": 18.0},
		]},
	{"title": "Wizard", "scene": "res://Wizard.tscn",
		"color": Color(0.36, 0.33, 0.66),
		"icon": [
			# built by tools/make_wizard_icon.ps1 from the exported Krita frames:
			# just the gnome
			{"tex": "res://art/wizard/icon.png", "pos": Vector2(-10, -12), "size": Vector2(126, 126)},
		]},
]

const ICON_SIZE := Vector2(110, 110)   ## the box icon layers are placed in (see LEVELS)
const ICON_SCALE := 1.45               ## ...shown this much bigger on a card
const CARD := Vector2(250, 290)
const MUSIC := "res://audio/music/menu"   ## + .wav / .ogg / .mp3
const MENU_BPM := 120.0
const MUSIC_DB := -6.0

const BG_TOP := Color(1.0, 0.95, 0.84)
const BG_BOTTOM := Color(0.98, 0.84, 0.68)
const INK := Color(0.2, 0.14, 0.12)
## The gold star on a level you've finished with 100%. Drawn in code until
## STAR_ART exists (draw it facing up, any size: it's fit into the star's box).
const STAR_ART := "res://art/menu/star.png"
const STAR_R := 34.0                   ## star size (radius, px)
const GOLD := Color(1.0, 0.8, 0.15)

var _cards: Array[Button] = []
var _bg: Control
var _music: AudioStreamPlayer
var _t := 0.0


func _ready() -> void:
	# First launch on this computer: calibrate timing before anything else.
	if not Settings.has_input_offset() and not Settings.calibration_offered:
		Settings.calibration_offered = true
		get_tree().change_scene_to_file.call_deferred("res://Calibrate.tscn")
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_bg = Control.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.draw.connect(_draw_bg)
	add_child(_bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	add_child(col)

	var title := Label.new()
	title.text = "RHYTHM GAME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 60)
	title.add_theme_color_override("font_color", INK)
	col.add_child(title)

	var sub := Label.new()
	sub.text = "pick a level"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", INK.lightened(0.35))
	col.add_child(sub)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 34)
	col.add_child(row)
	for lvl in LEVELS:
		# the card sits in a plain holder: containers reset scale/rotation, and the
		# card bounces and tilts
		var holder := Control.new()
		holder.custom_minimum_size = CARD + Vector2(0, 24)   # room to pop up
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(holder)
		var card := _make_card(lvl)
		card.position = Vector2(0, 12)
		holder.add_child(card)
		_cards.append(card)

	var cal_state := "%+d ms" % roundi(Settings.input_offset() * 1000.0) \
		if Settings.has_input_offset() else "not set"
	var cal := Button.new()
	cal.text = "Calibrate Timing  (%s)" % cal_state
	cal.custom_minimum_size = Vector2(340, 48)
	cal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cal.focus_mode = Control.FOCUS_ALL
	cal.add_theme_font_size_override("font_size", 18)
	_colour_button(cal, Color(0.42, 0.5, 0.62), 24)
	cal.pressed.connect(_play.bind("res://Calibrate.tscn"))
	cal.mouse_entered.connect(cal.grab_focus)
	col.add_child(cal)

	var hint := Label.new()
	hint.text = "Tap a game to play  -  II (or Esc) in a level to pause"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", INK.lightened(0.5))
	col.add_child(hint)

	# Down from any card goes to Calibrate, Up from Calibrate back to the cards
	for c in _cards:
		c.focus_neighbor_bottom = cal.get_path()
	cal.focus_neighbor_top = _cards[0].get_path()

	for c in _cards:
		if not c.disabled:
			c.grab_focus()
			break

	_music = AudioStreamPlayer.new()
	_music.volume_db = MUSIC_DB
	add_child(_music)
	for ext in ["wav", "ogg", "mp3"]:
		if ResourceLoader.exists("%s.%s" % [MUSIC, ext]):
			_music.stream = load("%s.%s" % [MUSIC, ext])
			_music.finished.connect(_music.play)    # loop
			_music.play()
			break


## A level card: coloured, rounded, the icon big on a light disc, the name below.
func _make_card(lvl: Dictionary) -> Button:
	var built := ResourceLoader.exists(lvl["scene"])
	var b := Button.new()
	b.size = CARD
	b.pivot_offset = CARD / 2.0
	b.disabled = not built
	b.focus_mode = Control.FOCUS_ALL
	var c: Color = lvl["color"]
	_colour_button(b, c, 26)

	var disc := Panel.new()
	var d := StyleBoxFlat.new()
	d.bg_color = c.lightened(0.55)
	d.set_corner_radius_all(90)
	disc.add_theme_stylebox_override("panel", d)
	disc.size = Vector2(180, 180)
	disc.position = Vector2((CARD.x - 180) / 2.0, 22)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(disc)

	var icon := _make_icon(lvl.get("icon", []))
	icon.position = Vector2((CARD.x - ICON_SIZE.x * ICON_SCALE) / 2.0, 32)
	icon.name = "Icon"
	b.add_child(icon)

	var name_l := Label.new()
	name_l.text = lvl["title"] if built else "%s\ncoming soon" % lvl["title"]
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.size = Vector2(CARD.x, 70)
	name_l.position = Vector2(0, 210)
	name_l.add_theme_font_size_override("font_size", 28)
	name_l.add_theme_color_override("font_color", Color.WHITE)
	name_l.add_theme_color_override("font_outline_color", c.darkened(0.35))
	name_l.add_theme_constant_override("outline_size", 6)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(name_l)

	# 100% on this level: a gold star in the top-right corner, poking out a little
	if built and Settings.is_perfect(lvl["scene"]):
		var star := Control.new()
		star.name = "Star"
		star.size = Vector2(STAR_R, STAR_R) * 2.0
		star.pivot_offset = star.size / 2.0
		star.position = Vector2(CARD.x - STAR_R * 1.35, -STAR_R * 0.65)
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star.draw.connect(_draw_star.bind(star))
		b.add_child(star)

	b.pressed.connect(_play.bind(lvl["scene"]))
	b.mouse_entered.connect(func(): if not b.disabled: b.grab_focus())
	return b


func _make_icon(layers: Array) -> Control:
	var inner := Control.new()        # layers are placed in ICON_SIZE space, then scaled up
	inner.scale = Vector2.ONE * ICON_SCALE
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for layer in layers:
		if not ResourceLoader.exists(layer["tex"]):
			continue
		var t := TextureRect.new()
		t.texture = load(layer["tex"])
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.position = layer["pos"]
		t.size = layer["size"]
		t.pivot_offset = t.size / 2.0
		t.rotation_degrees = layer.get("rot", 0.0)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(t)
	return inner


func _colour_button(b: Button, c: Color, radius: int) -> void:
	for st in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		b.add_theme_color_override(st, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))
	b.add_theme_stylebox_override("normal", _box(c, Color.TRANSPARENT, radius))
	b.add_theme_stylebox_override("hover", _box(c.lightened(0.1), Color.TRANSPARENT, radius))
	b.add_theme_stylebox_override("pressed", _box(c.darkened(0.15), INK, radius))
	b.add_theme_stylebox_override("focus", _box(Color.TRANSPARENT, INK, radius))
	b.add_theme_stylebox_override("disabled", _box(Color(0.6, 0.57, 0.52), Color.TRANSPARENT, radius))


func _box(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.draw_center = fill.a > 0.0
	s.set_corner_radius_all(radius)
	s.set_border_width_all(5 if border.a > 0.0 else 0)
	s.border_color = border
	s.content_margin_left = 20
	s.content_margin_right = 20
	return s


## Beats since the menu opened: from the song when there is one, else the clock.
func _beat() -> float:
	if _music and _music.playing:
		var pos := _music.get_playback_position() + AudioServer.get_time_since_last_mix() \
			- AudioServer.get_output_latency()
		return pos * MENU_BPM / 60.0
	return _t * MENU_BPM / 60.0


func _process(dt: float) -> void:
	_t += dt
	var beat := _beat()
	var phase := fposmod(beat, 1.0)
	var hit := pow(1.0 - phase, 3.0)            # 1 on the beat, easing off
	var tilt_dir := 1.0 if int(floor(beat)) % 2 == 0 else -1.0
	for i in _cards.size():
		var c := _cards[i]
		var picked := c.has_focus()
		var lift := -12.0 if picked else 0.0
		var s := 1.06 + 0.035 * hit if picked else 1.0
		c.position.y = lerpf(c.position.y, 12.0 + lift, 1.0 - exp(-dt * 14.0))
		c.scale = c.scale.lerp(Vector2(s, s), 1.0 - exp(-dt * 18.0))
		c.rotation_degrees = 2.5 * tilt_dir * hit if picked else 0.0
		# every icon bobs, each a little behind the one before
		var icon := c.get_node("Icon") as Control
		icon.position.y = 32.0 - 6.0 * absf(sin(PI * (beat - i * 0.25)))
		var star := c.get_node_or_null("Star") as Control
		if star:                                   # a little sway, a pop on the beat
			star.rotation_degrees = 8.0 * sin(PI * beat * 0.5)
			star.scale = Vector2.ONE * (1.0 + 0.08 * hit)


## The gold star: your drawing if STAR_ART exists, else a 5-point star in code.
func _draw_star(c: Control) -> void:
	var box := Rect2(Vector2.ZERO, c.size)
	if ResourceLoader.exists(STAR_ART):
		var tex: Texture2D = load(STAR_ART)
		var k := minf(box.size.x / tex.get_width(), box.size.y / tex.get_height())
		var sz := Vector2(tex.get_width(), tex.get_height()) * k
		c.draw_texture_rect(tex, Rect2(box.get_center() - sz * 0.5, sz), false)
		return
	var mid := box.get_center()
	var pts := PackedVector2Array()
	for i in 10:
		var r := STAR_R if i % 2 == 0 else STAR_R * 0.45
		var a := -PI / 2.0 + PI * i / 5.0
		pts.append(mid + Vector2(cos(a), sin(a)) * r)
	c.draw_colored_polygon(pts, GOLD)
	pts.append(pts[0])
	c.draw_polyline(pts, INK, 4.0, true)
	# a small shine on the upper left
	c.draw_circle(mid + Vector2(-STAR_R * 0.18, -STAR_R * 0.2), STAR_R * 0.12, Color(1, 1, 1, 0.75))


## Soft top-to-bottom gradient, BG_TOP to BG_BOTTOM.
func _draw_bg() -> void:
	var sz := _bg.size
	var steps := 24
	for i in steps:
		var y0 := sz.y * i / steps
		var y1 := sz.y * (i + 1) / steps
		_bg.draw_rect(Rect2(0, y0, sz.x, y1 - y0 + 1), BG_TOP.lerp(BG_BOTTOM, (i + 0.5) / steps))


func _play(scene: String) -> void:
	Transition.go(scene)               # fade to black, in, fade back
