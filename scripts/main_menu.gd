extends Control
## Level select. Built in code so adding a level is one entry in LEVELS.
##   Up/Down or mouse to pick, Enter/Space/click to play. Esc in a level comes back here.
## A level whose scene doesn't exist yet shows as "coming soon" and can't be picked.

const LEVELS := [
	{"title": "Monkey Business", "scene": "res://Rhythm.tscn",
		"color": Color(0.36, 0.62, 0.32),
		# icon layers, back to front: texture, top-left and size inside the ICON_SIZE box,
		# optional rot in degrees (spins around the layer's own centre)
		"icon": [
			{"tex": "res://art/monkey/coconut.png", "pos": Vector2(-8, -2), "size": Vector2(96, 96), "rot": -18.0},
			{"tex": "res://art/monkey/banana.png", "pos": Vector2(38, 30), "size": Vector2(80, 80), "rot": 22.0},
		]},
	{"title": "Grill Master","scene": "res://Grill.tscn",
		"color": Color(0.85, 0.42, 0.2),
		"icon": [
			{"tex": "res://art/grilling/icon/tongs.png", "pos": Vector2(-2, 0), "size": Vector2(74, 74), "rot": -10.0},
			{"tex": "res://art/grilling/icon/grill.png", "pos": Vector2(30, 20), "size": Vector2(94, 94), "rot": 18.0},
		]},
]

const ICON_SIZE := Vector2(110, 110)
const BG :=Color(0.99, 0.93, 0.8)
const INK := Color(0.2, 0.14, 0.12)

var _buttons: Array[Button] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.add_theme_constant_override("separation", 18)
	add_child(col)

	var title := Label.new()
	title.text = "RHYTHM GAME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", INK)
	col.add_child(title)

	var sub := Label.new()
	sub.text = "pick a level"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", INK.lightened(0.35))
	col.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	col.add_child(gap)

	for lvl in LEVELS:
		# every row gets an icon slot (empty if the level has no icon) so buttons stay lined up
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		row.add_child(_make_icon(lvl.get("icon", [])))
		var b := _make_button(lvl)
		row.add_child(b)
		col.add_child(row)
		_buttons.append(b)

	# smaller settings button under the levels, lined up with them
	var cal_state := "%+d ms" % roundi(Settings.input_offset() * 1000.0) \
		if Settings.has_input_offset() else "not set"
	var cal := _make_button({"title": "Calibrate Timing  (%s)" % cal_state,
		"scene": "res://Calibrate.tscn", "color": Color(0.42, 0.5, 0.62)})
	cal.custom_minimum_size = Vector2(460, 56)
	cal.add_theme_font_size_override("font_size", 20)
	var cal_row := HBoxContainer.new()
	cal_row.add_theme_constant_override("separation", 16)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(ICON_SIZE.x, 0)
	cal_row.add_child(spacer)
	cal_row.add_child(cal)
	col.add_child(cal_row)
	_buttons.append(cal)

	var hint := Label.new()
	hint.text = "Up/Down to choose  -  Enter to play  -  Esc in a level returns here"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", INK.lightened(0.5))
	col.add_child(hint)

	for b in _buttons:
		if not b.disabled:
			b.grab_focus()
			break


func _make_icon(layers: Array) -> Control:
	var box := Control.new()
	box.custom_minimum_size = ICON_SIZE
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
		box.add_child(t)
	return box


func _make_button(lvl: Dictionary) -> Button:
	var built := ResourceLoader.exists(lvl["scene"])
	var b := Button.new()
	var blurb: String = lvl.get("blurb", "") if built else "coming soon"
	b.text = lvl["title"] if blurb.is_empty() else "%s\n%s" % [lvl["title"], blurb]
	b.custom_minimum_size = Vector2(460, 92)
	b.disabled = not built
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))

	var c: Color = lvl["color"]
	b.add_theme_stylebox_override("normal", _box(c))
	b.add_theme_stylebox_override("hover", _box(c.lightened(0.12)))
	b.add_theme_stylebox_override("pressed", _box(c.darkened(0.15)))
	b.add_theme_stylebox_override("focus", _box(c.lightened(0.12), INK))
	b.add_theme_stylebox_override("disabled", _box(Color(0.6, 0.57, 0.52)))

	b.pressed.connect(_play.bind(lvl["scene"]))
	b.mouse_entered.connect(func(): if not b.disabled: b.grab_focus())
	return b


func _box(fill: Color, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(18)
	s.set_border_width_all(4 if border.a > 0.0 else 0)
	s.border_color = border
	s.content_margin_left = 20
	s.content_margin_right = 20
	return s


func _play(scene: String) -> void:
	get_tree().change_scene_to_file(scene)
