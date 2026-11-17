extends Control
## Credits: the cast joins in one at a time in their own level's scenery,
## each with their name next to them, and once they're on they stay -- so each
## scenery ends with the whole family together. Monkey, Bonkey and Surfkey on the beach, the grill
## critters in the backyard, the Gnome on the wizard tower. Opened from the
## Credits button on the main menu.
##   Hold Space / click / touch to speed it up.  Esc goes back to the menu.
##   After the last card it goes back to the menu by itself.
##
## Edit CAST to change who's in it, their names, order, size and where they stand.
## Edit MADE_BY for the last card.

const VP := Vector2(1152, 648)

## Each entry:
##   name    the name shown next to them
##   world   "beach", "backyard" or "tower" (the scenery behind them)
##   frames  their drawing(s). Two frames = they swap on every beat. "layers"
##           instead = drawings stacked on top of each other (the bear + his arm).
##   height  px on screen
##   foot    where the bottom-centre of the drawing goes
##   label   where the centre of their name goes
##   extra   more drawings on top (the gnome's hands): tex, and its top-left
##           in the main drawing's own px
## In each scenery they join in this order and stay; lower feet are drawn in front.
const CAST := [
	{"name": "Monkey", "world": "beach", "frames": ["res://art/monkey/monkey_idle.png"],
		"height": 360, "foot": Vector2(620, 710), "label": Vector2(610, 315)},
	{"name": "Bonkey", "world": "beach", "bonk": true,   # bumps the palm on every beat
		"frames": ["res://art/monkey/monkey_twist_0.png", "res://art/monkey/monkey_twist_1.png"],
		"height": 320, "foot": Vector2(190, 715), "label": Vector2(200, 430)},
	{"name": "Surfkey", "world": "beach", "surf": true,  # rides the sea, like his cameo
		"frames": ["res://art/monkey/monkey_surfing.png"], "height": 220, "foot": Vector2(930, 0),
		"label": Vector2(950, 270)},
	{"name": "Squirrel", "world": "backyard", "frames": ["res://art/grilling/critters/squirrel.png"],
		"height": 190, "foot": Vector2(520, 610), "label": Vector2(560, 390)},
	{"name": "Raccoon", "world": "backyard", "frames": ["res://art/grilling/critters/raccoon.png"],
		"height": 230, "foot": Vector2(870, 620), "label": Vector2(870, 360)},
	{"name": "Bear", "world": "backyard",
		# his flat, cut-off side (and the paw left of it) is the left 20% of
		# bear.png: `edge` slides that far off the left of the screen
		"edge": 0.25,
		"layers": ["res://art/grilling/critters/bear.png", "res://art/grilling/critters/bear_arm.png"],
		"height": 400, "foot": Vector2(0, 640), "label": Vector2(210, 225)},
	{"name": "Dave", "world": "backyard", "fly": true,   # last one in the backyard
		"frames": ["res://art/grilling/critters/bird.png"], "height": 150, "foot": Vector2(740, 300),
		"label": Vector2(740, 125)},
	{"name": "Gnome", "world": "tower", "shadow_x": 0.2,   # his feet are right of centre
		"frames": ["res://art/wizard/gnome_0.png", "res://art/wizard/gnome_1.png"],
		# his hands, where they sit on him in your Krita file (in gnome_0.png px)
		"extra": [{"tex": "res://art/wizard/gnome_hands.png", "at": Vector2(304.5, 171.5)}],
		"height": 300, "foot": Vector2(560, 590), "label": Vector2(600, 255)},
]
const MADE_BY := ["Made by", "Tommy Flick", "", "Thanks for playing!"]

const SHOT_S := 4.0             ## seconds per cast member (= 8 beats at 120 BPM)
const CARD_S := 3.5             ## the title card
const END_S := 6.0              ## the "Made by" card
const FADE_S := 0.35            ## fade to black when the scenery changes
const POP_S := 0.45             ## how long they take to pop in
const FAST := 4.0               ## speed while held
const NAME_SIZE := 52
const MUSIC := "res://audio/music/menu"   ## same song as the menu, if there is one
const BPM := 120.0

const CREAM_TOP := Color(1.0, 0.95, 0.84)
const CREAM_BOTTOM := Color(0.98, 0.84, 0.68)
const INK := Color(0.2, 0.14, 0.12)

# the beach (same numbers as Rhythm.tscn / coconut_game.gd)
const BEACH_SKY := Color(0.53, 0.79, 0.92)
const SAND := Color(0.93, 0.85, 0.62)
const OCEAN := Color("4f74b1")
const BEACH_GROUND := 560.0
const OCEAN_H := 80.0
const PALM := "res://art/monkey/palm_tree.png"
const PALM_FOOT := Vector2(320, 655)
const PALM_SCALE := 1.7
const SURF_WATERLINE := 0.745   ## where the flat sea is in monkey_surfing.png (fraction down)
const SURF_CLIP := 0.785

# the backyard (Grill.tscn)
const TABLE := "res://art/grilling/scene/table.png"
const TABLE_RECT := Rect2(60, 170, 490, 308)

# the wizard tower (wizard_game.gd)
const NIGHT := Color(0.106, 0.122, 0.231)
const HORIZON := 430.0
const ENEMY := Vector2(1010, 430)
const WALL_Y := 572.0

var _t := 0.0                   ## credits clock (runs faster while held)
var _shots: Array = []          ## {kind, world, member?, start, dur}
var _total := 0.0
var _tex := {}
var _stars: Array[Vector3] = []
var _back: Control              ## beach / tower / cream backdrops
var _field: Node2D              ## the backyard (grill level's own field)
var _front: Control             ## table, cast, names, fades
var _music: AudioStreamPlayer
var _leaving := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var t := 0.0
	_shots.append({"kind": "title", "world": "cream", "start": t, "dur": CARD_S})
	t += CARD_S
	for m in CAST:
		_shots.append({"kind": "cast", "world": m["world"], "member": m, "start": t, "dur": SHOT_S})
		t += SHOT_S
	_shots.append({"kind": "end", "world": "cream", "start": t, "dur": END_S})
	_total = t + END_S

	for m in CAST:
		for p in m.get("frames", []) + m.get("layers", []):
			_load(p)
		for e in m.get("extra", []):
			_load(e["tex"])
	for p in [PALM, TABLE]:
		_load(p)

	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 70:
		_stars.append(Vector3(rng.randf() * VP.x, rng.randf() * (HORIZON - 30.0), rng.randf_range(0.8, 2.2)))

	_back = _layer(_draw_back)
	_field = Node2D.new()
	_field.set_script(load("res://scripts/grill_field.gd"))
	_field.set("shadows", [] as Array[Rect2])
	_field.set("shadow_shapes", [PackedVector2Array([160, 200, 470, 285, 380, 350, 115, 255]),
		PackedVector2Array([75, 345, 305, 425, 298, 442, 64, 374])] as Array[PackedVector2Array])
	_field.set("shadow_drops", PackedVector2Array([10, 68, 8, 56]))
	add_child(_field)
	_front = _layer(_draw_front)

	var hint := Label.new()
	hint.text = "hold SPACE to speed up  -  Esc to go back"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	hint.add_theme_constant_override("outline_size", 4)
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


func _layer(fn: Callable) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(fn)
	add_child(c)
	return c


func _load(path: String) -> void:
	if not _tex.has(path) and ResourceLoader.exists(path):
		_tex[path] = load(path)


func _process(dt: float) -> void:
	var held := Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_t += dt * (FAST if held else 1.0)
	if _t >= _total:
		_back_to_menu()
		return
	_field.visible = _shot()["world"] == "backyard"
	_back.queue_redraw()
	_front.queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		_back_to_menu()


func _back_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	Transition.go("res://MainMenu.tscn")


func _shot_index() -> int:
	for i in range(_shots.size() - 1, -1, -1):
		if _t >= _shots[i]["start"]:
			return i
	return 0


func _shot() -> Dictionary:
	return _shots[_shot_index()]


func _beat() -> float:
	if _music and _music.playing:
		return (_music.get_playback_position() + AudioServer.get_time_since_last_mix()
			- AudioServer.get_output_latency()) * BPM / 60.0
	return _t * BPM / 60.0


# ---------------------------------------------------------------- backdrops

func _draw_back() -> void:
	match _shot()["world"]:
		"beach": _draw_beach()
		"tower": _draw_tower()
		"cream": _gradient(_back, CREAM_TOP, CREAM_BOTTOM)
		_: pass                          # backyard: the field node draws it


func _draw_beach() -> void:
	var c := _back
	var beat := _beat()
	c.draw_rect(Rect2(Vector2.ZERO, VP), BEACH_SKY)
	# the sea, with a couple of rows of swell strokes drifting left
	var top := BEACH_GROUND - OCEAN_H
	c.draw_rect(Rect2(0, top, VP.x, OCEAN_H + 2.0), OCEAN)
	c.draw_line(Vector2(0, top), Vector2(VP.x, top), OCEAN.lightened(0.25), 3.0)
	var rows := [[0.3, 210.0, 70.0], [0.62, 260.0, 95.0]]
	for r in rows.size():
		var row: Array = rows[r]
		var y: float = top + OCEAN_H * float(row[0])
		var gap: float = row[1]
		var x := -gap + fposmod(beat * (6.0 + r * 4.0), gap) + r * gap * 0.5
		while x < VP.x + gap:
			c.draw_line(Vector2(x, y), Vector2(x + float(row[2]), y + 2.0), OCEAN.darkened(0.12), 3.0)
			x += gap
	# Surfkey rides on the sea, in front of the swell and behind the beach
	var on := _on_screen()
	for j in on:
		if _shots[j]["member"].get("surf", false):
			_draw_surfer(_shots[j]["member"], _shots[j]["start"])
	# foam, then sand
	var wash := 3.0 * sin(fposmod(beat, 1.0) * PI)
	var pts := PackedVector2Array()
	for i in 49:
		var px := VP.x * i / 48.0
		pts.append(Vector2(px, BEACH_GROUND - 5.0 - wash + 2.5 * sin(px * 0.03 + beat * 0.8)))
	pts.append(Vector2(VP.x, BEACH_GROUND + 2.0))
	pts.append(Vector2(0, BEACH_GROUND + 2.0))
	c.draw_colored_polygon(pts, Color(1, 1, 1, 0.75))
	c.draw_rect(Rect2(0, BEACH_GROUND, VP.x, VP.y - BEACH_GROUND), SAND)
	# the palm: Bonkey rocks it on every beat
	if _tex.has(PALM):
		var tex: Texture2D = _tex[PALM]
		var angle := 0.0
		if on.any(func(j): return _shots[j]["member"].get("bonk", false)):
			var k := fposmod(beat, 1.0) / 0.6
			if k < 1.0:
				angle = -0.035 * sin(k * TAU * 1.5) * (1.0 - k)
		var sz := tex.get_size() * PALM_SCALE
		c.draw_set_transform(PALM_FOOT, angle, Vector2.ONE)
		c.draw_texture_rect(tex, Rect2(-sz.x * 0.5, -sz.y, sz.x, sz.y), false)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_surfer(m: Dictionary, start: float) -> void:
	var tex: Texture2D = _tex.get(m["frames"][0])
	if tex == null:
		return
	var k := _pop_k(start)
	var beat := _beat()
	var sz := tex.get_size() * (float(m["height"]) / tex.get_height())
	var x: float = m["foot"].x + (1.0 - k) * (VP.x - m["foot"].x + sz.x)   # glides in from the right
	var bob := -5.0 * sin(fposmod(beat, 1.0) * PI)
	var anchor := Vector2(x, BEACH_GROUND - OCEAN_H + 2.0 + bob)
	_back.draw_set_transform(anchor, 0.015 * sin(beat * PI * 0.5), Vector2.ONE)
	var src := Rect2(0, 0, tex.get_width(), tex.get_height() * SURF_CLIP)
	_back.draw_texture_rect_region(tex, Rect2(-sz.x * 0.5, -sz.y * SURF_WATERLINE, sz.x, sz.y * SURF_CLIP), src)
	_back.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_tower() -> void:
	var c := _back
	var pulse := exp(-fposmod(_beat(), 1.0) * 5.0)
	c.draw_rect(Rect2(Vector2.ZERO, VP), NIGHT)
	for s in _stars:
		c.draw_circle(Vector2(s.x, s.y), s.z, Color(1, 1, 1, 0.45 + 0.4 * pulse * (s.z / 2.2)))
	c.draw_circle(Vector2(820, 90), 34, Color(0.96, 0.93, 0.8))
	c.draw_circle(Vector2(806, 82), 30, NIGHT)          # crescent
	_ellipse(c, Vector2(900, HORIZON + 10), Vector2(420, 70), Color(0.23, 0.25, 0.39))
	_ellipse(c, Vector2(380, HORIZON + 18), Vector2(380, 52), Color(0.2, 0.22, 0.35))
	c.draw_rect(Rect2(0, HORIZON, VP.x, VP.y - HORIZON), Color(0.165, 0.2, 0.25))
	for x in [-400.0, 200.0, 700.0, 1500.0]:
		c.draw_line(ENEMY, Vector2(x, VP.y), Color(0.23, 0.27, 0.34), 1.0)
	# the battlements he stands on
	var stone := Color(0.42, 0.44, 0.52)
	var dark := Color(0.32, 0.33, 0.41)
	c.draw_rect(Rect2(0, WALL_Y, VP.x, VP.y - WALL_Y), stone)
	c.draw_rect(Rect2(0, WALL_Y, VP.x, 8), dark)
	var bx := -30.0
	while bx < VP.x:
		c.draw_rect(Rect2(bx, WALL_Y - 46, 84, 48), stone)
		c.draw_rect(Rect2(bx, WALL_Y - 46, 14, 48), dark)
		bx += 150.0


# ---------------------------------------------------------------- cast + names

func _draw_front() -> void:
	var s := _shot()
	var c := _front
	if s["world"] == "backyard" and _tex.has(TABLE):
		var tex: Texture2D = _tex[TABLE]
		var k := minf(TABLE_RECT.size.x / tex.get_width(), TABLE_RECT.size.y / tex.get_height())
		var sz := tex.get_size() * k
		c.draw_texture_rect(tex, Rect2(TABLE_RECT.get_center() - sz * 0.5, sz), false)
	match s["kind"]:
		"title":
			_text(c, "CREDITS", Vector2(VP.x / 2.0, VP.y / 2.0), 96, INK, true, _pop_k(s["start"]))
		"end":
			var y := VP.y / 2.0 - (MADE_BY.size() - 1) * 34.0
			for i in MADE_BY.size():
				var a := clampf((_t - s["start"] - i * 0.4) / 0.5, 0.0, 1.0)
				_text(c, MADE_BY[i], Vector2(VP.x / 2.0, y), 72 if i == 1 else 40, Color(INK, a), true, 1.0)
				y += 68.0
		"cast":
			var on := _on_screen()
			var order := on.duplicate()
			# feet lower on screen = nearer = drawn on top; flyers on top of all
			order.sort_custom(func(a, b): return _depth(_shots[a]["member"]) < _depth(_shots[b]["member"]))
			for j in order:
				_draw_member(_shots[j]["member"], _shots[j]["start"])
			for j in on:
				_draw_name(_shots[j]["member"], _shots[j]["start"])
	_draw_fade()


## Shot indexes of everyone on screen now: this scenery's cast so far.
func _on_screen() -> Array:
	var out := []
	var i := _shot_index()
	var world: String = _shots[i]["world"]
	while i >= 0 and _shots[i]["kind"] == "cast" and _shots[i]["world"] == world:
		out.push_front(i)
		i -= 1
	return out


func _depth(m: Dictionary) -> float:
	return 10000.0 if m.get("fly", false) else float(m["foot"].y)


## Draws a cast member (popping in from `start`, bobbing on the beat).
func _draw_member(m: Dictionary, start: float) -> void:
	if m.get("surf", false):
		return                                 # drawn by the beach, in the sea
	var paths: Array = m.get("layers", m.get("frames", []))
	if paths.is_empty() or not _tex.has(paths[0]):
		return
	var first: Texture2D = _tex[paths[0]]
	var sz := first.get_size() * (float(m["height"]) / first.get_height())
	var foot: Vector2 = m["foot"]
	if m.has("edge"):
		foot.x = sz.x * (0.5 - float(m["edge"]))   # that much of the drawing hangs off the left edge

	var beat := _beat()
	var hit := pow(1.0 - fposmod(beat, 1.0), 3.0)
	var pop := _pop_k(start)
	var sc := Vector2(1.0 + 0.04 * hit, 1.0 - 0.04 * hit) * _back_out(pop)
	var lift := 0.0
	if m.get("fly", false):
		lift = -14.0 * sin(beat * PI)          # Dave flaps up and down
	var tex_list: Array = []
	if m.has("layers"):
		for p in m["layers"]:
			if _tex.has(p):
				tex_list.append(_tex[p])
	else:
		var frames: Array = m["frames"]
		var f: String = frames[int(floor(beat)) % frames.size()]
		tex_list.append(_tex.get(f, first))
	var c := _front
	if not m.get("fly", false):              # a soft shadow under their feet
		_ellipse(c, foot + Vector2(sz.x * float(m.get("shadow_x", 0.0)), -4),
			Vector2(sz.x * 0.32 * pop, 12), Color(0, 0, 0, 0.18))
	c.draw_set_transform(foot + Vector2(0, lift), 0.0, sc)
	for t in tex_list:
		c.draw_texture_rect(t, Rect2(-sz.x * 0.5, -sz.y, sz.x, sz.y), false)
	var k := sz.x / first.get_width()       # drawing px -> screen px
	for e in m.get("extra", []):
		if _tex.has(e["tex"]):
			var et: Texture2D = _tex[e["tex"]]
			c.draw_texture_rect(et, Rect2(Vector2(-sz.x * 0.5, -sz.y) + e["at"] * k, et.get_size() * k), false)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Their name at their `label` spot, sliding in just after they arrive.
func _draw_name(m: Dictionary, start: float) -> void:
	var k := clampf((_t - start - 0.25) / 0.4, 0.0, 1.0)
	var ease_k := 1.0 - pow(1.0 - k, 3.0)
	var at: Vector2 = m["label"] + Vector2(0, 30.0 * (1.0 - ease_k))
	_text(_front, m["name"], at, NAME_SIZE, Color(1, 1, 1, k), true, k)


## Black fade when the scenery changes (and in from black at the very start).
func _draw_fade() -> void:
	var i := _shot_index()
	var s: Dictionary = _shots[i]
	var into: float = _t - s["start"]
	var left: float = s["start"] + s["dur"] - _t
	var a := 0.0
	if i == 0 or _shots[i - 1]["world"] != s["world"]:
		a = maxf(a, 1.0 - into / FADE_S)
	if i == _shots.size() - 1 or _shots[i + 1]["world"] != s["world"]:
		a = maxf(a, 1.0 - left / FADE_S)
	if a > 0.0:
		_front.draw_rect(Rect2(Vector2.ZERO, VP), Color(0, 0, 0, clampf(a, 0.0, 1.0)))


## 0 -> 1 over POP_S from `start`.
func _pop_k(start: float) -> float:
	return clampf((_t - start) / POP_S, 0.0, 1.0)


## Ease with a little overshoot, for the pop-in.
func _back_out(k: float) -> float:
	var s := 1.7
	var u := k - 1.0
	return 1.0 + u * u * ((s + 1.0) * u + s)


# ---------------------------------------------------------------- helpers

## Text with a dark outline. centred = centred on pos; else pos is its left-middle.
func _text(c: Control, s: String, pos: Vector2, fs: int, col: Color, centred: bool, a: float) -> void:
	if s == "" or a <= 0.0:
		return
	var font := ThemeDB.fallback_font
	var sz := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var at := Vector2(pos.x - (sz.x * 0.5 if centred else 0.0), pos.y + font.get_ascent(fs) * 0.5 - font.get_descent(fs) * 0.5)
	if col.r > 0.5:                          # light text gets a dark outline
		c.draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 12, Color(INK, a))
	c.draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _gradient(c: Control, top: Color, bottom: Color) -> void:
	var steps := 24
	for i in steps:
		var y0 := VP.y * i / steps
		c.draw_rect(Rect2(0, y0, VP.x, VP.y / steps + 1.0), top.lerp(bottom, (i + 0.5) / steps))


func _ellipse(c: Control, centre: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		pts.append(centre + Vector2(cos(a) * r.x, sin(a) * r.y))
	c.draw_colored_polygon(pts, col)
