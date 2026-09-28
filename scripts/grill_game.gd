extends Node2D
## "Grill Master" minigame. Call and response: the song plays an example (the
## tong clack-clack, a 3-part sizzle flip, the final pop) and the player answers
## it on the next bar with SPACE, in the same rhythm. Only the answers are graded.
##
## Chart: beatmaps/grill.tres -- cues { beat, cue: "tap" | "flip" | "pop",
## role: "call" | "answer" }. Flip and pop bars are 3 presses on beats 1-2-3.
##   Space / click  answer     R  restart     Esc  menu

const PERFECT := 0.075
const GOOD := 0.15
const MISS_TAIL := 0.03            ## seconds past the late edge of GOOD before it's a Miss
const VP := Vector2(1152, 648)
const INK := Color(0.2, 0.14, 0.12)

@export var beatmap: Beatmap
## Screen spots for the drawn-on effects.
@export var patty_pos := Vector2(605, 300)     ## steam rises from here on a sizzle
@export var bun_pos := Vector2(1010, 500)      ## where the patty lands on the pop

@onready var audio: AudioStreamPlayer = $AudioStreamPlayer
@onready var tongs: AnimatedSprite2D = $Stage/Tongs

var _answers: Array = []           ## compiled answer cues still to grade, in order
var _all: Array = []               ## every compiled cue (calls too) -- for bar positions
var score := 0
var combo := 0
var best_combo := 0
var _tally := {"Perfect": 0, "Good": 0, "Miss": 0}
var _fx: Array = []                ## { kind, t0 } -- steam puffs, pop, miss flash
var _landed := false               ## patty is on the bun (after the final pop)
var _finished := false
var _fx_layer: Node2D


func _ready() -> void:
	# effects + HUD draw above the grill art
	_fx_layer = Node2D.new()
	add_child(_fx_layer)
	_fx_layer.draw.connect(_draw_fx)

	Conductor.stream_player = audio
	if beatmap:
		Conductor.bpm = beatmap.bpm
		Conductor.first_beat_offset = beatmap.first_beat_offset
		Conductor.video_offset = beatmap.video_offset
		Conductor.input_offset = Settings.input_offset(beatmap.input_offset)
	Conductor.song_finished.connect(_on_finished)
	_restart()


## Conductor is an autoload and outlives this scene -- stop it before our
## AudioStreamPlayer is freed, or its _process would poke a dead node.
func _exit_tree() -> void:
	Conductor.song_finished.disconnect(_on_finished)
	Conductor.stop()
	Conductor.stream_player = null


func _restart() -> void:
	_all = beatmap.compiled(Conductor) if beatmap else []
	_answers = _all.filter(func(c): return c.get("role", "answer") == "answer")
	score = 0
	combo = 0
	best_combo = 0
	_tally = {"Perfect": 0, "Good": 0, "Miss": 0}
	_fx.clear()
	_landed = false
	_finished = false
	tongs.play(&"flip")
	tongs.stop()
	tongs.frame = 0
	Conductor.play()


func _on_finished() -> void:
	_finished = true


func _process(_dt: float) -> void:
	var now: float = Conductor.song_position
	# an answer nobody pressed for -> Miss
	while not _answers.is_empty() and now > _answers[0]["time"] + Conductor.input_offset + GOOD + MISS_TAIL:
		_grade(_answers.pop_front(), "Miss")
	_fx = _fx.filter(func(f): return now - f["t0"] < 1.2)
	_fx_layer.queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	var pressed: bool = (e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_SPACE) \
		or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
	if pressed:
		_press()
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_R:
				_restart()
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://MainMenu.tscn")


func _press() -> void:
	if _finished:
		return
	# grade against the next answer if this press is inside its window
	if not _answers.is_empty():
		var c: Dictionary = _answers[0]
		var err: float = Conductor.timing_error(c["beat"])
		if absf(err) <= GOOD:
			_answers.pop_front()
			_grade(c, "Perfect" if absf(err) <= PERFECT else "Good")
			return
	_play(&"tap")   # nothing to answer -- just clack the tongs


func _grade(c: Dictionary, grade: String) -> void:
	_tally[grade] += 1
	if grade == "Miss":
		combo = 0
		_fx.append({"kind": "miss", "t0": Conductor.song_position})
		return
	combo += 1
	best_combo = maxi(best_combo, combo)
	score += 100 if grade == "Perfect" else 50
	var part := int(fposmod(c["beat"], 4.0))   # flip / pop bars: beat 1, 2, 3 of the bar
	match c["cue"]:
		"tap":
			_play(&"tap")
		"flip", "pop":
			if part == 0:
				_play(&"flip")                     # beat 1: the flip itself
			elif c["cue"] == "pop" and part == 2:
				_landed = true                     # beat 3 of the pop bar: onto the bun
				_fx.append({"kind": "pop", "t0": Conductor.song_position})
			else:
				_fx.append({"kind": "steam", "t0": Conductor.song_position})


func _play(anim: StringName) -> void:
	tongs.stop()
	tongs.play(anim)


# --- drawing -----------------------------------------------------------------

func _draw_fx() -> void:
	var now := Conductor.song_position
	var font := ThemeDB.fallback_font
	var l := _fx_layer
	for f in _fx:
		var t: float = now - f["t0"]
		match f["kind"]:
			"steam":   # three puffs drifting up off the patty
				for i in 3:
					var p := patty_pos + Vector2((i - 1) * 26.0 + sin(t * 6.0 + i) * 6.0, -30.0 - t * 90.0 - i * 10.0)
					l.draw_circle(p, 10.0 + t * 14.0, Color(0.85, 0.85, 0.85, clampf(0.7 - t * 0.9, 0.0, 1.0)))
			"pop":     # burst where the patty lands
				for i in 8:
					var a := TAU * i / 8.0
					var r := 20.0 + t * 160.0
					l.draw_circle(bun_pos + Vector2(cos(a), sin(a)) * r + Vector2(0, -30),
						6.0 * (1.0 - clampf(t, 0.0, 1.0)), Color(1, 0.85, 0.3, clampf(1.0 - t, 0.0, 1.0)))
			"miss":    # brief smoky puff: burnt
				l.draw_circle(patty_pos + Vector2(0, -20 - t * 40.0), 18.0 + t * 30.0, Color(0.3, 0.3, 0.3, clampf(0.6 - t, 0.0, 1.0)))
	if _landed:
		_draw_burger(l)

	l.draw_string(font, Vector2(VP.x - 250, 52), "SCORE  %d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, INK)
	l.draw_string(font, Vector2(VP.x - 250, 88), "COMBO  x%d" % combo, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, INK)
	if _finished:
		_draw_results(l, font)


## Placeholder bun + patty until there's art for it.
func _draw_burger(l: Node2D) -> void:
	var b := bun_pos
	l.draw_set_transform(b + Vector2(0, 18), 0.0, Vector2(1.0, 0.35))
	l.draw_circle(Vector2.ZERO, 90.0, Color(0.87, 0.62, 0.3))             # bottom bun
	l.draw_set_transform(b, 0.0, Vector2(1.0, 0.3))
	l.draw_circle(Vector2.ZERO, 84.0, Color(0.36, 0.2, 0.12))              # patty
	l.draw_set_transform(b + Vector2(0, -26), 0.0, Vector2(1.0, 0.55))
	l.draw_circle(Vector2.ZERO, 88.0, Color(0.93, 0.68, 0.33))             # top bun
	l.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for s in [Vector2(-40, -56), Vector2(0, -66), Vector2(38, -54), Vector2(-14, -44), Vector2(20, -40)]:
		l.draw_circle(b + s, 4.0, Color(1, 0.96, 0.85))                   # sesame


func _draw_results(l: Node2D, font: Font) -> void:
	var box := Rect2(VP.x / 2 - 200, VP.y / 2 - 120, 400, 240)
	l.draw_rect(box, Color(0, 0, 0, 0.6))
	var x := box.position.x + 32
	var y := box.position.y + 54
	l.draw_string(font, Vector2(x, y), "RESULTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
	l.draw_string(font, Vector2(x, y + 50), "Perfect   %d" % _tally["Perfect"], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.7, 1.0, 0.6))
	l.draw_string(font, Vector2(x, y + 82), "Good      %d" % _tally["Good"], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.9, 0.5))
	l.draw_string(font, Vector2(x, y + 114), "Miss      %d" % _tally["Miss"], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.5, 0.5))
	l.draw_string(font, Vector2(x, y + 154), "Score %d   Best x%d" % [score, best_combo], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	l.draw_string(font, Vector2(x, y + 186), "R to replay  -  Esc for menu", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.8, 0.8))
