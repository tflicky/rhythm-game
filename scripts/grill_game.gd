extends Node2D
## "Grill Master" minigame. One move: flip the burgers.
##
## Call: on a call bar, raw patties drop onto the grill one per note of the bar's
## rhythm -- each lands on its beat with a SIZZLE (left to right across the grate).
## Answer: on the next bar, flip them back in the same rhythm, one SPACE per
## patty. Your tongs flip each one (the flip you drew: grab, toss) and it flies
## off the grill, browning on the way, straight onto a bun waiting on the picnic
## table (patty spot 1 -> bun 1, and so on). Then a critter steals it -- each
## burger gets the next steal in STEALS, in order (see "critters" below). Miss one and it chars and smokes on the grill. A press with
## nothing to flip just clicks the tongs.
##
## Starts with a short tutorial: one caption card, then practice over a metronome
## (listen, count-in, your turn) until `practice_goal` clean tries. The 1 & 2 &
## strip at the top shows where the presses go. S skips it.
##
## Chart: beatmaps/grill.tres -- cues { beat, cue: "flip", role: "call" | "answer" }.
## Each call bar's notes go to patty spots 1, 2, 3, 4 in order (4 at most); the
## answer bar after it has the same number of notes.
##   Space / click  flip     S  skip practice     R  restart     Esc  pause

enum Phase { CARD, PRACTICE, SONG, SHOT }

const PERFECT := 0.075
const GOOD := 0.15
const MISS_TAIL := 0.03            ## seconds past the late edge of GOOD before it's a Miss
const VP := Vector2(1152, 648)
const INK := Color(0.2, 0.14, 0.12)
## Every sound is a file in SFX_DIR named after its slot (.wav / .ogg / .mp3).
## See audio/sfx/grill/README.md.
const SFX_DIR := "res://audio/sfx/grill/"
const SFX_SLOTS := ["flip_cue_2", "flip", "sizzle", "tong", "bun", "top_bun"]
const COOK_SHADER := preload("res://shaders/patty_cook.gdshader")
const VIVID_SHADER := preload("res://shaders/vivid.gdshader")
## Your flip drawing, as separate layers (art/grilling/parts/): back arm, patty,
## front arm. Frame FLIP_GRAB is the grab (on your press), FLIP_TOP the top of the
## toss, FLIP_LAND the landing -- which is also the tongs' ready pose.
const PARTS_DIR := "res://art/grilling/parts/"
const FLIP_GRAB := 7
const FLIP_TOP := 12
const FLIP_LAND := 19
const FLIP_BEATS := 2.0            ## beats a patty takes from the grab to the landing (as drawn: grab, toss, land)
## The tongs do the same motion, but when the next flip is due sooner they hurry
## to fit (never below FLIP_MIN) and move on -- the patty keeps flying at its own pace.
const FLIP_MIN := 0.22
const FLIP_UP_K := 0.45            ## share of the flip spent tossing up (the rest is coming down)
## Where the flip drawing's canvas sits inside Stage (it lines its patty up with
## the grate). Spot offsets are measured from the patty in that drawing.
const DRAWING_AT := Vector2(125, 0)
const DROP_S := 0.12               ## a called patty falls this long, landing on its beat
const DROP_H := 70.0               ## ...from this far up (screen px)
const SQUASH_S := 0.18             ## the little squash when it lands
const THROW_H := 20.0              ## extra height (screen px) on the arc from the grill to the bun
## Your burger drawing (scene/bun.png, burger.png, top_bun.png -- all on one shared
## canvas so they line up): where its patty sits, in those PNGs' pixels. The patty
## you flip lands there, so the drawing is sized to match the flipped patty.
const BUN_PATTY := Rect2(0, 42, 179, 75)
const TOP_BUN_AFTER := 0.5         ## beats after the patty lands that the top bun lands (on the "&")
const TOP_BUN_DROP_S := 0.12       ## the top bun falls this long...
const TOP_BUN_DROP_H := 140.0      ## ...from this far up (burger PNG px)
## The steals, used in this order (burger 1 gets the first, burger 6 the first again).
##   squirrel  runs in along the table, grabs it, runs back out
##   bird      swoops in and catches it in mid-air, before it reaches the bun
##   raccoon   pops up from behind the table, grabs it, sinks back down
##   bear      walks in from the left behind the table, his arm swings up and
##             grabs it, lifts it to his mouth, EATS it (chomp + chew), backs out
const STEALS := ["squirrel", "bird", "raccoon", "bear"]
## Per steal, in beats: [coming in (ends at the grab), leaving with the burger].
## The grab lands on a beat (except the bird's, which is mid-flip).
const STEAL_BEATS := {
	"squirrel": [1.0, 1.5],
	"bird": [1.0, 1.5],
	"raccoon": [1.0, 1.5],
	"bear": [1.0, 2.0],
}
const BEAR_CHOMP_S := 0.12         ## the burger squashes into the bear's mouth this fast
## The bear's leaving time (0..1): arm lifts the burger to his mouth until LIFT (chomp!),
## chews until CHEW (arm going back down), then backs out.
const BEAR_LIFT := 0.25
const BEAR_CHEW := 0.6
## His drawing, in bear.png px (bear_arm.png is the same size, your arm layer on its own).
const BEAR_CHIN := Vector2(457, 234)       ## the point he's moved by
const BEAR_SHOULDER := Vector2(205, 262)   ## the arm turns around this
const BEAR_PAW := Vector2(270, 500)        ## where the burger sits in his paw
const BEAR_PX := 0.87                      ## bear.png px -> screen px (before bear_scale)
const BEAR_GRAB := -0.87                   ## arm turn (radians, - = up/forward) when the paw is on the burger
const BEAR_MOUTH := -1.4                   ## ...and when it's up at his mouth
const BEAR_ARM_FRONT := 0.45               ## arm turned past this: drawn over the table, not behind it
const BEAR_FRONT_LEG := Rect2(250, 305, 215, 286)   ## his front leg in bear.png: drawn in front of the table
## bear.png's body is cut off on its left; from this column (PNG px) leftward it's
## stretched off the screen, so he can be small and still never show the cut.
const BEAR_CUT := 96.0
## Critters drawn BEHIND the picnic table (it hides their legs) instead of over it.
const BEHIND_TABLE := ["bear", "raccoon"]
const FLY_CATCH := 1.8             ## beats after your press the bird catches the patty
const BURN_S := 0.25               ## a missed patty chars over this long...
const BURN_FADE_AFTER := 0.7       ## ...then after this long fades away
const BURN_FADE_S := 0.4
const DIP_MS := 140.0              ## a press with nothing to flip: the tongs dip and click
const GLIDE := 22.0                ## how fast the tongs slide to the next patty (1/s)
const BURNT := Color(0.32, 0.28, 0.27)
## Practice strip: how many beats of the bar before it shows (the "4 &" lead-in),
## and how early it moves on to the next bar -- so you see beat 1 coming.
const STRIP_LEAD := 1.0
## Practice rhythms, taking turns.
const PRACTICE_PATTERNS := [[0.0, 2.0], [0.0, 1.0, 2.0]]
## Practice shots (like the Wizard's): 1/2 is one burger, 2/2 two in a rhythm.
const SHOT_PATTERNS := [[0.0], [0.0, 2.0]]
const SHOT_CLICK_BEATS := 256      ## practice metronome length (one track, never restarted)
## Scenery you drew, under res://art/grilling/: name -> [file, placeholder box].
const ART_DIR := "res://art/grilling/"
const ART := {
	"salt": ["season/salt.png", Rect2(-18, -24, 36, 48)],
	"pepper": ["season/pepper.png", Rect2(-18, -24, 36, 48)],
	"picnic_table": ["scene/table.png", Rect2(9, 193, 408, 257)],   # drawn into `table_rect`
	"bun": ["scene/bun.png", Rect2(-34, -12, 68, 30)],    # the empty bottom bun waiting on the table
	"burger": ["scene/burger.png", Rect2(-34, -20, 68, 40)],   # bottom bun with the patty on it
	"top_bun": ["scene/top_bun.png", Rect2(-34, -30, 68, 20)],
	# critters: drawn facing RIGHT; the box's (0, 0) is where the burger goes (its mouth)
	# your Krita drawings, at their Krita size; the box's (0, 0) is on the mouth
	"squirrel": ["critters/squirrel.png", Rect2(-213, -63, 237, 138)],
	"bird": ["critters/bird.png", Rect2(-142, -65, 219, 100)],
	"raccoon": ["critters/raccoon.png", Rect2(-119, -63, 189, 163)],
	"bear": ["critters/bear.png", Rect2(-398, -204, 532, 514)],   # your Krita bear (body); placed by BEAR_CHIN
	"bear_arm": ["critters/bear_arm.png", Rect2(-398, -204, 532, 514)],   # his arm layer, same canvas
}

@export var beatmap: Beatmap

@export_group("Layout")
## Where the patties sit on the grate (screen px, their middles), in the order
## they're called: note 1 of a bar goes on spot 1, and so on.
@export var patty_spots := PackedVector2Array([Vector2(660, 332), Vector2(735, 288), Vector2(810, 332), Vector2(872, 288)])
## The buns waiting on the picnic table (screen px, where the patty lands).
## A flip from patty spot 1 lands on bun 1, and so on.
@export var bun_spots := PackedVector2Array([Vector2(170, 234), Vector2(218, 249), Vector2(265, 264), Vector2(313, 279)])
## How big a patty looks on its bun, compared to on the grill.
@export var bun_patty_scale := 0.75
## Where the squirrel comes from / runs off to (screen x, off the left edge).
@export var critter_exit_x := -240.0
## Where the bear waits / backs off to (his chin, screen x) -- far enough that he's all off screen.
@export var bear_exit_x := -110.0
## How big the bear is (1 = the size he'd be standing in front of the table). Smaller = further back.
@export var bear_scale := 0.6
## Nudge where he stops (screen px). By default his paw lands right on the burger.
@export var bear_reach := Vector2.ZERO
@export var salt_pos := Vector2(409, 253)            ## the salt shaker on the table (its middle)
@export var pepper_pos := Vector2(450, 270)          ## the pepper shaker next to it
## The picnic table, behind the grill: where it sits in your Krita scene.
@export var table_rect := Rect2(9, 193, 408, 257)

@export_group("Look")
## Colour pop over all the art (not the text/UI). 0 / 1.0 / 0 / 1.0 = the art
## exactly as drawn.
## Extra colour that goes mostly to dull, greyish colours (the grill metal, shadows).
@export_range(0.0, 1.5, 0.05) var art_vibrance: float = 0.5
## Extra colour on everything (1.0 = none).
@export_range(0.5, 2.0, 0.05) var art_saturation: float = 1.15
## Gentle contrast so the colours read crisp (0 = none).
@export_range(0.0, 0.5, 0.01) var art_contrast: float = 0.0
## Sunshine: lifts the midtones so it reads as a bright day (1.0 = none; much
## past 1.25 starts to look washed out).
@export_range(1.0, 1.6, 0.01) var art_light: float = 1.2

@export_group("Practice round")
@export var practice: bool = true
## Wizard-style practice: two short shots over one steady metronome (1 burger, then
## 2 in a rhythm), with the SPACE key and a closing square showing when to flip.
## A miss repeats the shot; after two misses the burger waits for your press.
## Then the title card. Off = the older Listen / Your turn strip practice.
@export var practice_shots: bool = true
## While the "Flip it!" card is up, show how it's played behind it: a burger drops
## with a sizzle and gets flipped a bar later, on a loop until SPACE.
@export var card_demo: bool = true
## Clean tries needed before the song.
@export var practice_goal: int = 2
@export var practice_metronome_db: float = -8.0
## A "get ready" bar between the example and your turn, until your first clean try.
@export var practice_count_in: bool = true

@onready var audio: AudioStreamPlayer = $AudioStreamPlayer
@onready var _stage: Node2D = $Stage

var _skip_btn: Button               ## phone: the Skip button during practice (null on a computer)
var _phase := Phase.CARD
var _practice_passed := false
var _song_stream: AudioStream
var _metronome: AudioStreamWAV
var _card_ms := 0
var _demo_next := 4.0             ## card demo: the beat the next demo burger sizzles on
var _shot_step := 0                ## practice shots: 0 = one burger, 1 = two
var _shot_fails := 0               ## misses on this shot; after 2 the burgers wait for you
var _shot_retry := false
var _shot_hold := false            ## this try waits for each press
var _shot_frozen := false          ## ...and is waiting right now
var _shot_cyc := {}                ## { you: [0 / 1 hit / 2 missed], failed }
var _shot_end := 0.0               ## song time this try is judged

var _patties: Array = []           ## { spot, t, beat, state, t0, sprite, mat, sounded, cyc, i }
var _answers: Array = []           ## { beat, time, patty, cyc, i } -- still to grade, in time order
var _answer_total := 0
var _cycles: Array = []            ## practice: { start, gap, pat, cues, you, strays, taps, failed, judged }
var _next_cycle := 4.0
var _cycle_count := 0
var _step_ok := 0                  ## practice: clean tries so far
var _tally := {"Perfect": 0, "Good": 0, "Miss": 0}
var _results: Results
var _finished := false
## After the song ends the music's clock stops, so the last burgers keep going on
## this one (seconds since the end; -1 = still playing) until every critter is
## gone and the buns are back -- then the results.
var _outro := -1.0
var _outro_pos := 0.0              ## song position when the music ended
var _calm := 0.0                   ## seconds since the last burger left the table
const OUTRO_REST := 0.8            ## ...how long to look at the fresh buns before the results
var _fx: Array = []                ## { kind, t0, pos, seed }

var _frames := {}                  ## part name -> Array[Texture2D] (frames 0..FLIP_LAND)
var _patty_c := Vector2.ZERO       ## the patty's middle in the drawing (texture px)
var _home := Vector2.ZERO          ## ...on screen, where the drawing puts it
var _back: Sprite2D                ## your tongs: back arm (behind the patty)...
var _front: Sprite2D               ## ...and front arm (in front of it)
var _tong_off := Vector2.ZERO      ## where the tongs are now (stage px from the drawing's spot)
var _flip := {}                    ## the flip in progress: { patty, t0 }
var _dip_ms := -10000
var _art := {}
var _sfx := {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _panel_sb: StyleBoxFlat
var _back_layer: Node2D            ## behind the grill: the picnic table + shakers
var _fx_layer: Node2D              ## steam and smoke, over the patties, under the tongs
var _critter_layer: Node2D         ## the burger thieves: over the table, under a carried burger
var _behind_layer: Node2D          ## critters in BEHIND_TABLE: under the table
var _critters: Array = []          ## { kind, patty, t0, catch_t, end_t, at, pos, face, alpha }
var _steal_n := 0                  ## burgers stolen so far (picks the next steal in STEALS)
var _frame_c: Array[Vector2] = []  ## flip_patty frame i: where the patty is vs. frame 0 (texture px)
var _burger_k := 1.0               ## burger PNG px -> Stage px
var _bun_gone := {}                ## bun spot -> true once the song's last burger on it was carried off
var _ui_layer: Node2D              ## practice strip, cards, results: over everything
var _pause: PauseMenu


func _ready() -> void:
	_pause = PauseMenu.attach(self, _restart)   # Esc: Continue / Retry / Quit
	_skip_btn = TutorialUI.add_skip_button(self, _skip_practice)   # phone only
	_results = Results.new()
	add_child(_results)
	_back_layer = Node2D.new()
	add_child(_back_layer)
	move_child(_back_layer, _stage.get_index())
	_back_layer.draw.connect(_draw_back)
	_behind_layer = Node2D.new()
	add_child(_behind_layer)
	move_child(_behind_layer, _back_layer.get_index())
	_behind_layer.draw.connect(func(): _draw_critters(_behind_layer, true))
	_critter_layer = Node2D.new()
	_critter_layer.z_index = 1         # over a burger on its bun (z 0), under a carried / flying one (z 2)
	add_child(_critter_layer)
	_critter_layer.draw.connect(func(): _draw_critters(_critter_layer, false))
	_fx_layer = Node2D.new()
	add_child(_fx_layer)
	_fx_layer.draw.connect(_draw_fx)
	if art_vibrance != 0.0 or art_saturation != 1.0 or art_contrast != 0.0 or art_light != 1.0:
		var bright := ColorRect.new()          # re-colours everything drawn under z 9
		bright.size = VP
		bright.z_index = 9
		bright.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bm := ShaderMaterial.new()
		bm.shader = VIVID_SHADER
		bm.set_shader_parameter("vibrance", art_vibrance)
		bm.set_shader_parameter("saturation", art_saturation)
		bm.set_shader_parameter("contrast", art_contrast)
		bm.set_shader_parameter("light", art_light)
		bright.material = bm
		add_child(bright)
	_ui_layer = Node2D.new()
	_ui_layer.z_index = 10            # the flipping patty and front arm go up to z 3
	add_child(_ui_layer)
	_ui_layer.draw.connect(_draw_ui)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_panel_sb = StyleBoxFlat.new()
	_panel_sb.bg_color = Color(1, 0.97, 0.88)
	_panel_sb.set_corner_radius_all(18)
	_panel_sb.set_border_width_all(4)
	_panel_sb.border_color = INK

	for part in ["flip_back", "flip_front", "flip_patty"]:
		var frames: Array[Texture2D] = []
		for i in FLIP_LAND + 1:
			frames.append(load("%s%s/%s_%02d.png" % [PARTS_DIR, part, part, i]))
		_frames[part] = frames
	_patty_c = Rect2(_frames["flip_patty"][0].get_image().get_used_rect()).get_center()
	for tex: Texture2D in _frames["flip_patty"]:
		_frame_c.append(Rect2(tex.get_image().get_used_rect()).get_center() - _patty_c)
	_home = _stage.position + (DRAWING_AT + _patty_c) * _stage.scale.x
	# your burger drawing, sized so its patty is as wide as the patty you flip onto it
	var landed_w: float = (_frames["flip_patty"][0] as Texture2D).get_image().get_used_rect().size.x * bun_patty_scale
	_burger_k = landed_w / BUN_PATTY.size.x
	var tong_mat := ShaderMaterial.new()      # just the outline (the tongs are grey)
	tong_mat.shader = COOK_SHADER
	_back = _make_sprite(1, tong_mat)
	_front = _make_sprite(3, tong_mat)

	_song_stream = audio.stream
	Conductor.stream_player = audio
	if beatmap:
		Conductor.bpm = beatmap.bpm
		Conductor.first_beat_offset = beatmap.first_beat_offset
		Conductor.video_offset = beatmap.video_offset
		Conductor.input_offset = Settings.input_offset(beatmap.input_offset)
	Conductor.song_finished.connect(_on_song_finished)
	_load_sounds()
	# entering the level: the sound your press makes -- the tongs, click-click
	_play("tong", -4.0)
	get_tree().create_timer(0.16).timeout.connect(_play.bind("tong", -4.0))
	_restart()


func _make_sprite(z: int, mat: Material) -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.offset = -_patty_c              # positioned and scaled around the patty's middle
	s.z_index = z
	s.material = mat
	_stage.add_child(s)
	return s


## Your sound files (null for a slot with no file: it stays silent).
func _load_sounds() -> void:
	for slot: String in SFX_SLOTS:
		var s := load_sound(SFX_DIR, slot)
		if s:
			_sfx[slot] = s
		else:
			print("[grill] no sound file for slot '%s' in %s" % [slot, SFX_DIR])


## `dir`/`slot`.wav, .ogg or .mp3 -- whichever exists -- or null.
## (Also used by grill_one_burger.gd.)
static func load_sound(dir: String, slot: String) -> AudioStream:
	for ext in ["wav", "ogg", "mp3"]:
		var path := "%s%s.%s" % [dir, slot, ext]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null


## Conductor is an autoload and outlives this scene -- stop it before our
## AudioStreamPlayer is freed, or its _process would poke a dead node.
func _exit_tree() -> void:
	Conductor.song_finished.disconnect(_on_song_finished)
	Conductor.stop()
	Conductor.stream_player = null


# --- flow --------------------------------------------------------------------------

func _restart() -> void:
	if practice and not _practice_passed and practice_shots:
		_start_shots()
	elif practice and not _practice_passed:
		_show_card()
	else:
		_start_song()


func _reset_round() -> void:
	for p in _patties:
		if is_instance_valid(p["sprite"]):
			p["sprite"].queue_free()
	_patties.clear()
	_critters.clear()
	_bun_gone.clear()
	_steal_n = 0
	_answers.clear()
	_cycles.clear()
	_fx.clear()
	_flip = {}
	_finished = false
	_outro = -1.0
	_calm = 0.0
	_tally = {"Perfect": 0, "Good": 0, "Miss": 0}
	if _results:
		_results.reset()
	_tong_off = _spot_off(0)
	_dip_ms = -10000


func _show_card() -> void:
	Conductor.stop()
	_reset_round()
	_phase = Phase.CARD
	_card_ms = Time.get_ticks_msec()
	if card_demo:
		_start_card_demo()


## The demo behind the card: the practice metronome, one burger every two bars.
func _start_card_demo() -> void:
	_reset_round()
	_demo_next = 4.0             # one bar of clicks first
	if _metronome == null:
		_metronome = ClickTrack.make(Conductor.bpm, 64, Conductor.beats_per_measure, Conductor.first_beat_offset)
	audio.stream = _metronome
	audio.volume_db = practice_metronome_db
	Conductor.play()


## Card demo: queue the next burger (sizzle on the call beat, flip a bar later).
func _schedule_card_demo() -> void:
	if Conductor.song_position_in_beats < _demo_next - 1.0:
		return
	var p := _new_patty(0, _demo_next, null)
	var ab := _demo_next + 4.0
	_answers.append({"beat": ab, "time": Conductor.time_of_beat(ab), "patty": p, "cyc": null, "i": 0})
	_demo_next += 8.0


# --- practice shots ----------------------------------------------------------------

func _start_shots() -> void:
	Conductor.stop()
	_reset_round()
	_phase = Phase.SHOT
	audio.stream = ClickTrack.make(Conductor.bpm, SHOT_CLICK_BEATS, Conductor.beats_per_measure, Conductor.first_beat_offset)
	audio.volume_db = practice_metronome_db
	Conductor.play()
	_queue_shot(0, false)


## One try: the burgers sizzle on the call bar, you flip them on the next bar.
## The metronome keeps going; the try starts on the next downbeat.
func _queue_shot(step: int, retry: bool) -> void:
	_shot_step = step
	_shot_retry = retry
	_shot_fails = _shot_fails + 1 if retry else 0
	_shot_hold = _shot_fails >= 2
	_shot_frozen = false
	_reset_round()
	var start := 4.0
	if Conductor.song_position_in_beats > 0.5:
		start = ceilf((Conductor.song_position_in_beats + 1.0) / 4.0) * 4.0
	var pat: Array = SHOT_PATTERNS[step]
	_shot_cyc = {"start": start, "gap": 0.0, "pat": pat, "cues": [], "you": [], "strays": [],
		"taps": [], "failed": false, "judged": true}   # same shape as a practice try
	for i in pat.size():
		_shot_cyc["cues"].append(0)
		_shot_cyc["you"].append(0)
		var pt := _new_patty(i, start + pat[i], _shot_cyc)
		var ab: float = start + 4.0 + pat[i]
		_answers.append({"beat": ab, "time": Conductor.time_of_beat(ab), "patty": pt, "cyc": _shot_cyc, "i": i})
	_answer_total = _answers.size()
	_shot_end = _answers[-1]["time"] + 2.2   # room for the last flip and the hop to the table


func _update_shots(now: float) -> void:
	if _shot_hold and not _shot_frozen and not _answers.is_empty() \
			and Conductor.visual_position >= _answers[0]["time"] + Conductor.input_offset:
		_shot_frozen = true            # the burger waits on the grill for your press
	if _shot_frozen or now < _shot_end:
		return
	var ok: bool = not _shot_cyc["failed"] and not (_shot_cyc["you"] as Array).has(0)
	if not ok:
		_queue_shot(_shot_step, true)
	elif _shot_step + 1 < SHOT_PATTERNS.size():
		_queue_shot(_shot_step + 1, false)
	else:
		_practice_passed = true
		_show_card()                   # title card, then SPACE for the song


## The waiting burger gets flipped by this press; the rest of the try moves back
## by however long it waited, so the rhythm stays the same.
func _press_frozen() -> void:
	var a: Dictionary = _answers.pop_front()
	var late: float = Conductor.live_position() - Conductor.input_offset - a["time"]
	for b in _answers:
		b["time"] += late
		b["beat"] += late / Conductor.seconds_per_beat
	_shot_frozen = false
	_hit(a, 0.0)
	if not _answers.is_empty():
		_shot_end = _answers[-1]["time"] + 2.2
	else:
		_shot_end = Conductor.song_position + 2.2


func _start_practice() -> void:
	_reset_round()
	_phase = Phase.PRACTICE
	_step_ok = 0
	_cycle_count = 0
	_next_cycle = 4.0            # one bar of clicks first
	if _metronome == null:
		_metronome = ClickTrack.make(Conductor.bpm, 64, Conductor.beats_per_measure, Conductor.first_beat_offset)
	audio.stream = _metronome
	audio.volume_db = practice_metronome_db
	Conductor.play()


func _start_song() -> void:
	_phase = Phase.SONG
	_reset_round()
	audio.stream = _song_stream
	audio.volume_db = 0.0
	# group the chart by bar: a call bar's notes are its patties, the answer bar
	# after it flips them in the same order
	var calls := {}
	var answers := {}
	for c in (beatmap.compiled(Conductor) if beatmap else []):
		var bar := int(floor(c["beat"] / 4.0))
		var into: Dictionary = calls if c.get("role", "answer") == "call" else answers
		if not into.has(bar):
			into[bar] = []
		into[bar].append(c)
	for bar: int in calls:
		var cs: Array = calls[bar]
		cs.sort_custom(func(a, b): return a["beat"] < b["beat"])
		var ans: Array = answers.get(bar + 1, [])
		ans.sort_custom(func(a, b): return a["beat"] < b["beat"])
		for i in mini(cs.size(), patty_spots.size()):
			var p := _new_patty(i, cs[i]["beat"], null)
			if i < ans.size():
				_answers.append({"beat": ans[i]["beat"], "time": ans[i]["time"], "patty": p, "cyc": null, "i": i})
	_answers.sort_custom(func(a, b): return a["time"] < b["time"])
	_answer_total = _answers.size()
	Conductor.play()


func _new_patty(spot: int, beat: float, cyc: Variant) -> Dictionary:
	var p := {"spot": spot, "beat": beat, "t": Conductor.time_of_beat(beat), "state": "wait",
		"t0": 0.0, "sprite": null, "mat": null, "sounded": false, "cyc": cyc, "i": spot}
	_patties.append(p)
	return p


func _on_song_finished() -> void:
	if _phase == Phase.SONG:
		_outro = 0.0                   # results once the last steals are done (_process)
		_outro_pos = Conductor.song_position
	elif _phase == Phase.SHOT:
		_start_shots()                 # the metronome ran out (a very long wait): start over
	elif _phase == Phase.CARD and card_demo:
		_start_card_demo()             # the metronome ran out: loop the demo


## Practice: queue the next try (call bar, maybe a count-in bar, answer bar) a
## beat before it starts.
func _schedule_practice() -> void:
	if Conductor.song_position_in_beats < _next_cycle - 1.0:
		return
	var pat: Array = PRACTICE_PATTERNS[_cycle_count % PRACTICE_PATTERNS.size()]
	_cycle_count += 1
	var gap := 4.0 if practice_count_in and _step_ok == 0 else 0.0
	var cyc := {"start": _next_cycle, "gap": gap, "pat": pat, "cues": [], "you": [],
		"strays": [], "taps": [], "failed": false, "judged": false}
	for i in pat.size():
		cyc["cues"].append(0)
		cyc["you"].append(0)
		var p := _new_patty(i, _next_cycle + pat[i], cyc)
		var ab: float = _next_cycle + 4.0 + gap + pat[i]
		_answers.append({"beat": ab, "time": Conductor.time_of_beat(ab), "patty": p, "cyc": cyc, "i": i})
	_cycles.append(cyc)
	if _cycles.size() > 3:
		_cycles.pop_front()
	_next_cycle += 8.0 + gap


## Practice: once a try's answer bar is (nearly) over, count it if it was clean.
func _judge_practice() -> void:
	var b := Conductor.song_position_in_beats
	for cyc in _cycles:
		if cyc["judged"] or b < cyc["start"] + 8.0 + cyc["gap"] - 0.25 or (cyc["you"] as Array).has(0):
			continue
		cyc["judged"] = true
		if cyc["failed"]:
			continue
		_step_ok += 1
		if _step_ok >= practice_goal:     # done: straight into the song
			_practice_passed = true
			_start_song()
			return


# --- per frame -------------------------------------------------------------------

func _process(dt: float) -> void:
	if _skip_btn:
		_skip_btn.visible = _phase in [Phase.PRACTICE, Phase.SHOT]
	$Field.cameo_on = _phase == Phase.SONG   # the football throw is for the real song only
	if _phase != Phase.CARD or (card_demo and Conductor.playing):
		if _phase == Phase.PRACTICE:
			_judge_practice()
		if _phase == Phase.PRACTICE:
			_schedule_practice()
		var now: float = Conductor.song_position
		if _outro >= 0.0:                  # the music's over: carry on by frame time (stops when paused)
			_outro += dt
			now = _outro_pos + _outro
		var vis: float = now + Conductor.video_offset
		var latency := AudioServer.get_output_latency()
		if _phase == Phase.SHOT:
			_update_shots(now)
		if _phase == Phase.CARD:
			_schedule_card_demo()
			# the demo flips by itself, exactly when a perfect press would land
			while not _answers.is_empty() and now >= _answers[0]["time"] + Conductor.input_offset:
				_hit(_answers.pop_front(), 0.0)
		# the call sizzles, fired output-latency early so they're heard on the beat
		for p in _patties:
			if not p["sounded"] and now >= p["t"] - latency:
				p["sounded"] = true
				_play("flip_cue_2", -2.0)
		# a patty nobody flipped -> Miss
		while not _answers.is_empty() and not (_phase == Phase.SHOT and _shot_hold) \
				and now > _answers[0]["time"] + Conductor.input_offset + GOOD + MISS_TAIL:
			_miss(_answers.pop_front())
		_drive_patties(vis)
		_drive_critters(vis)
		_fx = _fx.filter(func(f): return now - f["t0"] < 1.5)
		if _outro >= 0.0 and not _finished:
			var busy := not _critters.is_empty() or _patties.any(
				func(p): return p["state"] in ["flip", "bun", "carried"])
			_calm = 0.0 if busy else _calm + dt
			if _calm >= OUTRO_REST or _outro > 10.0:
				_finished = true
	_drive_tongs(Conductor.visual_position, dt)   # on the card too, so they're there from the start
	_back_layer.queue_redraw()
	_fx_layer.queue_redraw()
	_critter_layer.queue_redraw()
	_behind_layer.queue_redraw()
	_ui_layer.queue_redraw()


## Stage px from the drawing's own patty to spot `i`.
func _spot_off(i: int) -> Vector2:
	if patty_spots.is_empty():
		return Vector2.ZERO
	return (patty_spots[clampi(i, 0, patty_spots.size() - 1)] - _home) / _stage.scale.x


func _to_stage(screen: Vector2) -> Vector2:
	return (screen - _stage.position) / _stage.scale.x


## Each patty through its life: waiting -> dropping onto the grill (lands on its
## beat) -> raw -> flipping (tossed off the grill onto its bun) -> on the bun ->
## stolen. Or burnt on the grill -> fades.
func _drive_patties(vis: float) -> void:
	for p in _patties:
		var st: String = p["state"]
		if st == "wait":
			if vis < p["t"] - DROP_S:
				continue
			var mat := ShaderMaterial.new()
			mat.shader = COOK_SHADER
			mat.set_shader_parameter("raw", 1.0)
			p["mat"] = mat
			p["sprite"] = _make_sprite(0, mat)
			p["sprite"].texture = _frames["flip_patty"][0]
			p["state"] = "drop"
			st = "drop"
			# a patty still sitting on this grill spot makes way
			for q in _patties:
				if q != p and q["spot"] == p["spot"] and q["state"] in ["burnt", "raw"]:
					q["state"] = "gone"
		var s: Sprite2D = p["sprite"]
		var at: Vector2 = DRAWING_AT + _patty_c + _spot_off(p["spot"])
		match st:
			"drop":
				var k := clampf((vis - (p["t"] - DROP_S)) / DROP_S, 0.0, 1.0)
				s.position = at + Vector2(0, -DROP_H * (1.0 - k * k)) / _stage.scale.x
				if vis >= p["t"]:
					p["state"] = "raw"
					p["t0"] = p["t"]
					_add_fx("steam", patty_spots[p["spot"]])
					_add_fx("bubbles", patty_spots[p["spot"]])
					if p["cyc"] != null:
						p["cyc"]["cues"][p["i"]] = 1
			"raw":
				var u: float = vis - p["t0"]
				var sq := 0.22 * sin(clampf(u / SQUASH_S, 0.0, 1.0) * PI) * (1.0 - clampf(u / SQUASH_S, 0.0, 1.0))
				s.position = at
				s.scale = Vector2(1.0 + sq, 1.0 - sq)
				# cooks on the grill: raw when it lands, perfectly brown right on its flip beat
				var due := _flip_due_time(p)
				if due > p["t0"]:
					p["mat"].set_shader_parameter("raw", 1.0 - clampf((vis - p["t0"]) / (due - p["t0"]), 0.0, 1.0))
			"flip":
				# your drawing up to the top of the toss; on the way down the patty
				# also travels over to its bun, browning as it goes
				var u: float = vis - p["t0"]
				var up: float = p["dur"] * FLIP_UP_K
				var k := clampf((u - up) / (p["dur"] - up), 0.0, 1.0)
				var to := _to_stage(_bun_spot(p["spot"]))
				s.position = at.lerp(to, smoothstep(0.0, 1.0, k)) 					+ Vector2(0, -THROW_H * sin(PI * k)) / _stage.scale.x
				s.scale = Vector2.ONE * lerpf(1.0, bun_patty_scale, k)
				s.texture = _frames["flip_patty"][_flip_frame(u, p["dur"])]
				# whatever's left of the raw (an early flip) cooks off in the air
				p["mat"].set_shader_parameter("raw", p.get("raw_left", 0.0) * (1.0 - clampf(u / p["dur"], 0.0, 1.0)))
				if p.has("critter") and vis >= p["critter"]["catch_t"]:
					p["state"] = "carried"         # the bird got it
					s.texture = _frames["flip_patty"][0]
				elif u >= p["dur"]:
					_land(p, vis)
			"bun":     # sitting on its bun, the top bun dropping on; its critter is on the way
				s.position = _to_stage(_bun_spot(p["spot"]))
				var base := _burger_k if p.has("top") else bun_patty_scale
				var u: float = vis - p["t0"]
				if p.has("top"):
					var t: Sprite2D = p["top"]
					var k := clampf((vis - (p["top_t"] - TOP_BUN_DROP_S)) / TOP_BUN_DROP_S, 0.0, 1.0)
					t.visible = k > 0.0
					t.position = Vector2(0, -TOP_BUN_DROP_H * (1.0 - k * k))
					if k >= 1.0 and not p.get("top_on", false):
						p["top_on"] = true
						_play("top_bun", -6.0)
					if p.get("top_on", false):
						u = vis - p["top_t"]       # squash again when the top bun lands
				var q := clampf(u / SQUASH_S, 0.0, 1.0)
				var sq := 0.15 * sin(q * PI) * (1.0 - q)
				s.scale = Vector2(1.0 + sq, 1.0 - sq) * base
				if vis >= p["critter"]["catch_t"]:
					p["state"] = "carried"
					s.z_index = 2
					s.scale = Vector2.ONE * base
					if p.has("top"):
						(p["top"] as Sprite2D).visible = true
						(p["top"] as Sprite2D).position = Vector2.ZERO
			"carried": # in a critter's mouth (_drive_critters moves it)
				pass
			"burnt":
				var u: float = vis - p["t0"]
				s.position = at
				s.scale = Vector2.ONE
				var col: Color = Color.WHITE.lerp(BURNT, clampf(u / BURN_S, 0.0, 1.0))
				col.a = 1.0 - clampf((u - BURN_FADE_AFTER) / BURN_FADE_S, 0.0, 1.0)
				s.modulate = col
				if col.a <= 0.0:
					p["state"] = "gone"
	for p in _patties:
		if p["state"] == "gone" and is_instance_valid(p["sprite"]):
			p["sprite"].queue_free()
	_patties = _patties.filter(func(p): return p["state"] != "gone")


## The flip's frame, `u` seconds after the grab.
func _flip_frame(u: float, dur: float) -> int:
	var up := dur * FLIP_UP_K
	if u < up:
		return roundi(lerpf(FLIP_GRAB, FLIP_TOP, u / up))
	return roundi(lerpf(FLIP_TOP, FLIP_LAND, clampf((u - up) / (dur - up), 0.0, 1.0)))


func _bun_spot(i: int) -> Vector2:
	if bun_spots.is_empty():
		return patty_spots[i]
	return bun_spots[clampi(i, 0, bun_spots.size() - 1)]


## When patty `p` is due to be flipped (song seconds), or -1 if it isn't waiting for a flip.
func _flip_due_time(p: Dictionary) -> float:
	for a in _answers:
		if a["patty"] == p:
			return a["time"]
	return -1.0


## Is bun `i` part of a finished burger right now (on the table or in a critter's mouth)?
func _bun_taken(i: int) -> bool:
	for p in _patties:
		if p["spot"] == i and p.has("top") and p["state"] in ["bun", "carried"]:
			return true
	return false


## The patty lands on its bun. Anything still on that bun is taken first.
func _land(p: Dictionary, vis: float) -> void:
	p["state"] = "bun"
	p["t0"] = vis
	p["mat"].set_shader_parameter("raw", 0.0)
	var s: Sprite2D = p["sprite"]
	s.texture = _frames["flip_patty"][0]
	s.scale = Vector2.ONE * bun_patty_scale
	s.position = _to_stage(_bun_spot(p["spot"]))
	s.z_index = 0
	_play("bun", -6.0)
	# your drawing takes over: the patty on its bun, and the top bun on its way down
	var burger := _tex("burger")
	var top := _tex("top_bun")
	if burger and top:
		s.material = null
		s.texture = burger
		s.offset = -BUN_PATTY.get_center()
		s.scale = Vector2.ONE * _burger_k
		var t := Sprite2D.new()
		t.centered = false
		t.offset = s.offset
		t.texture = top
		t.visible = false
		s.add_child(t)
		p["top"] = t
		p["top_t"] = vis + TOP_BUN_AFTER * Conductor.seconds_per_beat
	_send_critter(p, vis)


# --- critters steal the burgers -----------------------------------------------------
# Each burger gets the next steal in STEALS. A critter comes in (STEAL_BEATS[0]),
# grabs the burger at `catch_t`, and leaves with it in its mouth (STEAL_BEATS[1]).
# Most come once the burger is on its bun; the bird is sent at your
# press so it can catch the patty mid-flip. Art slots: art/grilling/critters/.

## Pick patty `p`'s steal (on your press). The bird sets off now; the
## others wait for the burger to land on its bun (`_send_critter`).
func _pick_steal(p: Dictionary) -> void:
	p["steal"] = STEALS[_steal_n % STEALS.size()]
	_steal_n += 1
	if p["steal"] == "bird":
		_add_critter(p, "bird", p["t0"] + FLY_CATCH * Conductor.seconds_per_beat)


func _send_critter(p: Dictionary, vis: float) -> void:
	if p.has("critter"):
		return
	var kind: String = p.get("steal", STEALS[0])
	_add_critter(p, kind, vis + STEAL_BEATS[kind][0] * Conductor.seconds_per_beat)


func _add_critter(p: Dictionary, kind: String, catch_t: float) -> void:
	var spb := Conductor.seconds_per_beat
	var c := {"kind": kind, "patty": p, "catch_t": catch_t,
		"t0": catch_t - STEAL_BEATS[kind][0] * spb, "end_t": catch_t + STEAL_BEATS[kind][1] * spb,
		"at": _bun_spot(p["spot"]), "pos": Vector2(-1000, -1000), "face": 1.0, "alpha": 1.0}
	p["critter"] = c
	_critters.append(c)


## Where the patty you see is right now (screen px). In the flip drawing it moves
## around inside its frame, so this adds that frame's offset.
func _patty_screen(p: Dictionary) -> Vector2:
	var s: Sprite2D = p["sprite"]
	var i: int = _frames["flip_patty"].find(s.texture)
	var off: Vector2 = _frame_c[i] if i >= 0 else Vector2.ZERO
	return _stage.position + (s.position + off * s.scale) * _stage.scale.x


## Every critter's spot this frame. u: 0..1 coming in (1 = the grab),
## v: 0..1 leaving. A carried burger rides in its mouth.
func _drive_critters(vis: float) -> void:
	for c in _critters:
		var b: Vector2 = c["at"]
		var u := clampf((vis - c["t0"]) / (c["catch_t"] - c["t0"]), 0.0, 1.0)
		var v := clampf((vis - c["catch_t"]) / (c["end_t"] - c["catch_t"]), 0.0, 1.0)
		var leaving: bool = vis >= c["catch_t"]
		var k := v if leaving else u
		var pos := b
		var face := 1.0
		var alpha := 1.0
		match c["kind"]:
			"squirrel":          # scurries in from the left along the table, scurries back
				var from := Vector2(critter_exit_x, b.y)
				pos = b.lerp(from, k * k) if leaving else from.lerp(b, 1.0 - (1.0 - k) * (1.0 - k))
				pos.y -= 6.0 * absf(sin(k * PI * 6.0))
				face = -1.0 if leaving else 1.0
			"bird":              # swoops down from the top left onto the patty, then off right and up
				var p: Dictionary = c["patty"]
				if not leaving:
					var meet: Vector2 = _patty_screen(p) if is_instance_valid(p["sprite"]) else b
					c["meet"] = meet
					pos = Vector2(-100, -80).lerp(meet, u) + Vector2(0, 60.0 * sin(u * PI))
				else:
					pos = (c.get("meet", b) as Vector2).lerp(Vector2(VP.x + 140, -120), v * v)
			"raccoon":           # pops up from behind the table, grab, sinks back down
				var under := b + Vector2(0, 110)
				pos = b.lerp(under, k * k) if leaving else under.lerp(b, 1.0 - (1.0 - k) * (1.0 - k))
				alpha = clampf((1.0 - k) * 4.0, 0.0, 1.0) if leaving else clampf(k * 4.0, 0.0, 1.0)
			"bear":              # walks in, arm grabs, lifts to mouth, chomp, chew, backs out
				var sc := BEAR_PX * bear_scale
				var stop := b + bear_reach - sc * (BEAR_SHOULDER - BEAR_CHIN + (BEAR_PAW - BEAR_SHOULDER).rotated(BEAR_GRAB))
				var from := Vector2(bear_exit_x, stop.y + 20)
				var arm := 0.0
				if not leaving:
					pos = from.lerp(stop, 1.0 - (1.0 - k) * (1.0 - k))
					pos.y -= 6.0 * absf(sin(k * PI * 3.0))       # lumbering steps
					arm = BEAR_GRAB * smoothstep(0.55, 1.0, k)    # reaching for it
				elif v < BEAR_LIFT:
					pos = stop
					arm = lerpf(BEAR_GRAB, BEAR_MOUTH, smoothstep(0.0, 1.0, v / BEAR_LIFT))
				elif v < BEAR_CHEW:
					var w := (v - BEAR_LIFT) / (BEAR_CHEW - BEAR_LIFT)
					pos = stop + Vector2(0, 8.0 * absf(sin(w * PI * 3.0)))    # chomp, chew, chew
					arm = BEAR_MOUTH * (1.0 - smoothstep(0.0, 0.7, w))
				else:
					var w := (v - BEAR_CHEW) / (1.0 - BEAR_CHEW)
					pos = stop.lerp(from, w * w)
				c["arm"] = arm
				c["paw"] = pos + sc * (BEAR_SHOULDER - BEAR_CHIN + (BEAR_PAW - BEAR_SHOULDER).rotated(arm))
		c["pos"] = pos
		c["face"] = face
		c["alpha"] = alpha
		var pt: Dictionary = c["patty"]
		if c["kind"] == "bear" and leaving and pt["state"] == "carried" and is_instance_valid(pt["sprite"]):
			# in his paw up to his mouth, then squashed flat by the chomp and gone
			var s: Sprite2D = pt["sprite"]
			var chomp_t: float = c["catch_t"] + BEAR_LIFT * (c["end_t"] - c["catch_t"])
			var e := clampf((vis - chomp_t) / BEAR_CHOMP_S, 0.0, 1.0)
			var base := _burger_k if pt.has("top") else bun_patty_scale
			s.z_index = 2
			if e <= 0.0:
				s.position = _to_stage(c["paw"])
			s.scale = Vector2(1.0 + 0.3 * e, 1.0 - e) * base
			s.visible = e < 1.0
		elif leaving and pt["state"] == "carried" and is_instance_valid(pt["sprite"]):
			var s: Sprite2D = pt["sprite"]
			s.z_index = 2
			s.position = _to_stage(pos)
			s.scale = Vector2.ONE * (_burger_k if pt.has("top") else bun_patty_scale)
			s.modulate.a = alpha
		if vis >= c["end_t"]:
			pt["state"] = "gone"
			# the song's last burger off this bun: the bun went with it, and no new one comes
			if _phase == Phase.SONG and pt.has("top") and not _patties.any(
					func(q): return q["spot"] == pt["spot"] and q["state"] in ["wait", "drop", "raw", "flip"]):
				_bun_gone[pt["spot"]] = true
	_critters = _critters.filter(func(c): return vis < c["end_t"])


## The critters (labelled placeholder boxes until you draw them), facing the way they go.
func _draw_critters(l: Node2D, behind: bool) -> void:
	for c in _critters:
		if Conductor.visual_position < c["t0"]:
			continue
		var box: Rect2 = ART[c["kind"]][1]
		var tex := _tex(c["kind"])
		var a: float = c["alpha"]
		if tex and c["kind"] == "bear":
			_draw_bear(l, c, tex, behind)      # body behind the table, arm over it once raised
			continue
		if (c["kind"] in BEHIND_TABLE) != behind:
			continue
		var pos: Vector2 = c["pos"]
		l.draw_set_transform(pos, 0.0, Vector2(c["face"], 1.0))
		if tex:
			var k := minf(box.size.x / tex.get_width(), box.size.y / tex.get_height())
			var sz := Vector2(tex.get_width(), tex.get_height()) * k
			l.draw_texture_rect(tex, Rect2(box.get_center() - sz * 0.5, sz), false, Color(1, 1, 1, a))
		else:
			_placeholder(l, box, c["kind"], a, 1.0)
		l.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The bear, in bear.png px. Behind the table: his body (and his arm while it hangs
## down behind it); over the table: his front leg, and his arm once it's reaching up.
func _draw_bear(l: Node2D, c: Dictionary, tex: Texture2D, behind: bool) -> void:
	var arm_tex := _tex("bear_arm")
	var ang: float = c.get("arm", 0.0)
	var arm_front := absf(ang) > BEAR_ARM_FRONT
	var sc := BEAR_PX * bear_scale
	var col := Color(1, 1, 1, c["alpha"])
	var h := float(tex.get_height())
	var w := float(tex.get_width())
	var draw_arm := func():         # turned around his shoulder
		var at: Vector2 = c["pos"] + sc * (BEAR_SHOULDER - BEAR_CHIN)
		l.draw_set_transform(at, ang, Vector2(sc, sc))
		l.draw_texture(arm_tex, -BEAR_SHOULDER, col)
	if behind:
		if arm_tex and not arm_front:
			draw_arm.call()            # hanging down behind his body
		l.draw_set_transform(c["pos"], 0.0, Vector2(sc, sc))
		var o := -BEAR_CHIN
		# his body runs on off the left of the screen: stretch the cut edge out there
		l.draw_texture_rect_region(tex, Rect2(o.x - 4000.0, o.y, 4000.0 + BEAR_CUT, h), Rect2(BEAR_CUT, 0, 2, h), col)
		l.draw_texture_rect_region(tex, Rect2(o.x + BEAR_CUT, o.y, w - BEAR_CUT, h),
			Rect2(BEAR_CUT, 0, w - BEAR_CUT, h), col)
	else:
		# his front leg again, over the table, so it's in front of the table's leg
		l.draw_set_transform(c["pos"], 0.0, Vector2(sc, sc))
		l.draw_texture_rect_region(tex, Rect2(BEAR_FRONT_LEG.position - BEAR_CHIN, BEAR_FRONT_LEG.size),
			BEAR_FRONT_LEG, col)
		if arm_tex and arm_front:
			draw_arm.call()            # reaching up, over the table and his leg
	l.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Your tongs: the flip at a patty's spot while one is going, else the ready pose
## (the landing frame) gliding over to the next patty you'll flip.
func _drive_tongs(vis: float, dt: float) -> void:
	var frame := FLIP_LAND
	var dip := 0.0
	if not _flip.is_empty() and vis - _flip["t0"] >= _flip["dur"]:
		_flip = {}                     # the tongs are done (the patty may still be in the air)
	if not _flip.is_empty():
		var p: Dictionary = _flip["patty"]
		_tong_off = _spot_off(p["spot"])
		frame = _flip_frame(vis - _flip["t0"], _flip["dur"])
	else:
		if not _answers.is_empty():
			var next: Dictionary = _answers[0]
			if next["time"] - Conductor.song_position < 2.0 * Conductor.seconds_per_beat:
				_tong_off = _tong_off.lerp(_spot_off(next["patty"]["spot"]), 1.0 - exp(-dt * GLIDE))
		var ms := float(Time.get_ticks_msec() - _dip_ms)
		if ms < DIP_MS:
			dip = 14.0 * sin(PI * ms / DIP_MS)
	for pair in [[_back, "flip_back"], [_front, "flip_front"]]:
		var s: Sprite2D = pair[0]
		s.texture = _frames[pair[1]][frame]
		s.position = DRAWING_AT + _patty_c + _tong_off + Vector2(0, dip)


# --- input -------------------------------------------------------------------------

## S on a computer, the Skip button on a phone.
func _skip_practice() -> void:
	if _phase != Phase.SONG:
		_practice_passed = true
		_start_song()


func _unhandled_input(e: InputEvent) -> void:
	var button: bool = (e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_SPACE) \
		or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT)
	if button:
		if _phase == Phase.CARD:
			if Time.get_ticks_msec() - _card_ms > 400:
				if _practice_passed or not practice:
					_start_song()
				else:
					_start_practice()
		elif _finished:
			_restart()                 # results: tap to play again
		elif _phase == Phase.SHOT and _shot_frozen:
			_press_frozen()
		else:
			_press()
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_S:
				_skip_practice()
			KEY_R:
				_restart()
			KEY_ESCAPE:
				if _finished:               # results screen: straight to the menu
					get_tree().change_scene_to_file("res://MainMenu.tscn")
				else:
					_pause.open()
				get_viewport().set_input_as_handled()


func _press() -> void:
	if _finished:
		return
	# the earliest patty still to flip that this press is close enough to
	for a in _answers:
		var err: float = Conductor.timing_error(a["beat"])
		if absf(err) <= GOOD:
			_answers.erase(a)
			_hit(a, err)
			return
		if err < -GOOD:
			break
	_stray()


func _hit(a: Dictionary, err: float) -> void:
	_tally["Perfect" if absf(err) <= PERFECT else "Good"] += 1
	var p: Dictionary = a["patty"]
	if p["state"] in ["wait", "drop"]:
		return
	p["state"] = "flip"
	if p.get("mat") != null:
		p["raw_left"] = float(p["mat"].get_shader_parameter("raw"))
	p["t0"] = Conductor.visual_position
	p["dur"] = FLIP_BEATS * Conductor.seconds_per_beat
	# the tongs: the same motion, hurried if the next flip is due before it would end
	var tong_dur: float = p["dur"]
	if not _answers.is_empty():
		tong_dur = clampf(_answers[0]["time"] - a["time"] - 0.03, FLIP_MIN, p["dur"])
	(p["sprite"] as Sprite2D).z_index = 2
	_flip = {"patty": p, "t0": p["t0"], "dur": tong_dur}
	_pick_steal(p)
	_play("flip", -2.0)
	var cyc: Variant = a["cyc"]
	if cyc != null:
		cyc["you"][a["i"]] = 1
		cyc["taps"].append(a["beat"] + err / Conductor.seconds_per_beat - _answer_bar(cyc))


func _miss(a: Dictionary) -> void:
	_tally["Miss"] += 1
	var p: Dictionary = a["patty"]
	if p["state"] in ["raw", "drop", "wait"]:
		p["state"] = "burnt"
		p["t0"] = Conductor.visual_position
		if is_instance_valid(p["sprite"]):
			(p["sprite"] as Sprite2D).scale = Vector2.ONE
		_add_fx("smoke", patty_spots[p["spot"]])
	var cyc: Variant = a["cyc"]
	if cyc != null:
		cyc["you"][a["i"]] = 2
		cyc["failed"] = true


## A press with nothing to flip: the tongs click. In practice it spoils the try.
func _stray() -> void:
	_dip_ms = Time.get_ticks_msec()
	_play("tong", -4.0)
	if _phase != Phase.PRACTICE:
		return
	var b := Conductor.song_position_in_beats - Conductor.input_offset / Conductor.seconds_per_beat
	for cyc in _cycles:
		var ab := _answer_bar(cyc)
		if b >= ab - 0.5 and b < ab + 4.0:
			cyc["strays"].append(b - ab)
			cyc["failed"] = true
			return


## Practice: the beat a try's answer bar starts on.
func _answer_bar(cyc: Dictionary) -> float:
	return cyc["start"] + 4.0 + cyc["gap"]


func _play(key: String, db: float) -> void:
	if not _sfx.has(key):
		return
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = _sfx[key]
	p.volume_db = db
	p.play()


func _add_fx(kind: String, pos: Vector2) -> void:
	_fx.append({"kind": kind, "t0": Conductor.song_position, "pos": pos, "seed": randi()})


# --- drawing -----------------------------------------------------------------------

## Behind the grill: the picnic table with the salt and pepper on it.
func _draw_back() -> void:
	var l := _back_layer
	var tex := _tex("picnic_table")
	if tex:
		var k := minf(table_rect.size.x / tex.get_width(), table_rect.size.y / tex.get_height())
		var sz := Vector2(tex.get_width(), tex.get_height()) * k
		l.draw_texture_rect(tex, Rect2(table_rect.get_center() - sz * 0.5, sz), false)
	else:
		_placeholder(l, table_rect, "picnic_table", 1.0, 1.0)
	var bun := _tex("bun")
	for i in bun_spots.size():
		if _bun_taken(i) or _bun_gone.has(i):
			continue                 # its burger (your drawing, bun and all) is sitting there / being carried off
		if bun:
			var k := _burger_k * _stage.scale.x
			l.draw_texture_rect(bun, Rect2(bun_spots[i] - BUN_PATTY.get_center() * k,
				Vector2(bun.get_width(), bun.get_height()) * k), false)
		else:
			_draw_art(l, "bun", bun_spots[i], 1.0)
	for season in ["salt", "pepper"]:
		var p: Vector2 = salt_pos if season == "salt" else pepper_pos
		var pts := PackedVector2Array()
		for i in 20:
			var a := TAU * i / 20.0
			pts.append(p + Vector2(0, 23) + Vector2(cos(a) * 20.0, sin(a) * 5.0))
		l.draw_colored_polygon(pts, Color(0.35, 0.22, 0.05, 0.35))
		_draw_art(l, season, p, 1.0)


## Steam, grease bubbles and smoke, over the patties and under the tongs.
func _draw_fx() -> void:
	var l := _fx_layer
	var now := Conductor.song_position
	for f in _fx:
		var t: float = maxf(now - f["t0"], 0.0)
		var pos: Vector2 = f["pos"]
		match f["kind"]:
			"steam":   # three puffs drifting up off the patty
				for i in 3:
					var p := pos + Vector2((i - 1) * 22.0 + sin(t * 6.0 + i) * 5.0, -20.0 - t * 80.0 - i * 8.0)
					l.draw_circle(p, 8.0 + t * 12.0, Color(0.9, 0.9, 0.9, clampf(0.65 - t * 0.9, 0.0, 1.0)))
			"bubbles":   # grease bubbles swelling up off the grate and popping
				var rng := RandomNumberGenerator.new()
				rng.seed = f["seed"]
				for i in 6:
					var d := rng.randf() * 0.1
					var k := clampf((t - d) / 0.45, 0.0, 1.0)
					if k > 0.0 and k < 1.0:
						var p := pos + Vector2(rng.randf_range(-40, 40), -6.0 - k * rng.randf_range(20, 50))
						l.draw_arc(p, rng.randf_range(4, 8) * (0.5 + k), 0.0, TAU, 16, Color(1.0, 0.8, 0.5, 1.0 - k), 3.0)
			"smoke":   # burnt: dark smoke rolling up
				for i in 3:
					var k := clampf((t - i * 0.12) / 1.1, 0.0, 1.0)
					if k > 0.0 and k < 1.0:
						var p := pos + Vector2(sin(k * 5.0 + i) * 10.0, -10.0 - k * 110.0)
						l.draw_circle(p, 12.0 + k * 26.0, Color(0.25, 0.24, 0.24, 0.6 * (1.0 - k)))


## The tutorial card and strip, and the results: over everything.
func _draw_ui() -> void:
	var l := _ui_layer
	var font := ThemeDB.fallback_font
	match _phase:
		Phase.CARD:
			_draw_card(l, font)
		Phase.PRACTICE:
			_draw_practice(l, font)
		Phase.SHOT:
			_draw_shots(l, font)
	if _finished:
		var box := Rect2(VP.x / 2 - 200, VP.y / 2 - 95, 400, 220)
		l.draw_rect(box, Color(0.12, 0.08, 0.06, 0.82))
		_results.draw_percent(l, font, box.get_center() + Vector2(0, -10), _tally["Perfect"] + _tally["Good"], _answer_total)
		l.draw_string(font, Vector2(box.position.x, box.end.y - 18), "Tap to play again", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 18, Color(0.8, 0.8, 0.8))


func _draw_card(l: Node2D, font: Font) -> void:
	l.draw_rect(Rect2(Vector2.ZERO, VP), Color(0, 0, 0, 0.18))
	if practice_shots:                 # after the practice shots: just the title
		var tr := Rect2(VP.x * 0.5 - 200, VP.y * 0.5 - 75, 400, 150)
		l.draw_style_box(_panel_sb, tr)
		l.draw_string(font, Vector2(tr.position.x, tr.position.y + 62), "GRILL MASTER", HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 40, INK)
		l.draw_string(font, Vector2(tr.position.x, tr.position.y + 112), "Tap to start", HORIZONTAL_ALIGNMENT_CENTER, tr.size.x, 22, Color(INK, 0.7))
		return
	var r := _caption(l, font, "Burgers sizzle?  Flip them back, same rhythm.", "Flip it!")
	var blink := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 250.0)
	l.draw_string(font, Vector2(r.end.x - 130, r.end.y - 12), "SPACE", HORIZONTAL_ALIGNMENT_RIGHT, 116, 16, Color(INK, blink))


func _caption(l: Node2D, font: Font, text: String, title := "") -> Rect2:
	var h := 58.0 if title == "" else 96.0
	var r := Rect2(VP.x * 0.5 - 380, VP.y - h - 18, 760, h)
	l.draw_style_box(_panel_sb, r)
	var y := r.position.y + 37.0
	if title != "":
		l.draw_string(font, Vector2(r.position.x, y), title, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 30, INK)
		y += 38.0
	l.draw_string(font, Vector2(r.position.x, y), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 22, Color(0.6, 0.32, 0.08))
	return r


func _draw_practice(l: Node2D, font: Font) -> void:
	var b := Conductor.visual_position / Conductor.seconds_per_beat
	var strip := Rect2(VP.x * 0.5 - 270, 10, 540, 128)
	# The strip moves on to the next bar STRIP_LEAD beats early, so you watch the
	# playhead come in through the lead-in ("4 &") and land on beat 1.
	var bs := b + STRIP_LEAD
	var cyc: Variant = null
	for c in _cycles:
		if bs >= c["start"] and bs < c["start"] + 8.0 + c["gap"]:
			cyc = c
	if cyc == null:
		_draw_strip(l, font, strip, [], [], b - 4.0 * ceilf(b / 4.0), [], "Get ready", INK, INK)
	elif bs < cyc["start"] + 4.0:
		_draw_strip(l, font, strip, cyc["pat"], cyc["cues"], b - cyc["start"], [],
			"Listen", Color(0.75, 0.4, 0.1), Color(1.0, 0.6, 0.2))
	elif bs < cyc["start"] + 4.0 + cyc["gap"]:
		_draw_strip(l, font, strip, cyc["pat"], [], b - cyc["start"] - 4.0, [],
			"Get ready", Color(0.25, 0.4, 0.75), Color(1, 0.88, 0.3))
	else:
		_draw_strip(l, font, strip, cyc["pat"], cyc["you"], b - _answer_bar(cyc), cyc["strays"],
			"Your turn!", Color(0.7, 0.45, 0.0), Color(0.36, 0.62, 0.32), cyc["taps"])
	# the count-in: a big 4, 3, 2, 1 over your tongs, popping on each beat
	for c in _cycles:
		if b >= c["start"] + 4.0 and b < _answer_bar(c):
			var into: float = b - c["start"] - 4.0
			var pulse := 1.0 + 0.35 * exp(-fposmod(into, 1.0) * 8.0)
			var at: Vector2 = (patty_spots[0] if not patty_spots.is_empty() else VP / 2.0) + Vector2(-60, -110)
			l.draw_set_transform(at, 0.0, Vector2(pulse, pulse))
			l.draw_string_outline(font, Vector2(-60, 24), str(4 - int(into)), HORIZONTAL_ALIGNMENT_CENTER, 120, 72, 12, INK)
			l.draw_string(font, Vector2(-60, 24), str(4 - int(into)), HORIZONTAL_ALIGNMENT_CENTER, 120, 72, Color(1, 0.88, 0.3))
			l.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# clean tries so far: small dots in the strip's top-right corner
	for i in practice_goal:
		var c := Vector2(strip.end.x - 22 - 24 * (practice_goal - 1 - i), strip.position.y + 24)
		if i < _step_ok:
			l.draw_circle(c, 8.0, Color(0.36, 0.62, 0.32))
		else:
			l.draw_arc(c, 8.0, 0.0, TAU, 24, Color(INK, 0.4), 2.5)
	l.draw_string(font, Vector2(VP.x - 120, VP.y - 8), "S: skip", HORIZONTAL_ALIGNMENT_RIGHT, 110, 14, Color(INK, 0.45))


## Practice shots: the caption, TAP box and closing square (TutorialUI -- the
## same boxes in the same spot in every level). While a burger waits for you,
## the square pulses.
func _draw_shots(l: Node2D, _font: Font) -> void:
	var head := "Try again!" if _shot_retry else "Practice  %d/%d" % [_shot_step + 1, SHOT_PATTERNS.size()]
	var sub := "Sizzle?  Flip it!" if _shot_step == 0 else "Two sizzles?  Flip both!"
	TutorialUI.caption(l, head, sub)
	TutorialUI.skip_hint(l)
	var live := not _answers.is_empty()
	TutorialUI.tap_box(l, live)
	if live:
		TutorialUI.square(l, _answers[0]["time"] + Conductor.input_offset - Conductor.visual_position,
			_shot_frozen, GOOD)


## One bar as a timeline: a faded lead-in ("4 &" of the bar before, STRIP_LEAD
## beats), then beats 1-4 with "&"s. A circle on each beat of `pat`, filled as
## `marks` says (0 empty, 1 hit, 2 missed), red X for extra presses, a tick where
## each counted press landed, and a playhead at `head` beats into the bar (it
## shows from -STRIP_LEAD, so you see it coming into beat 1).
func _draw_strip(l: Node2D, font: Font, r: Rect2, pat: Array, marks: Array, head: float,
		strays: Array, title: String, title_col: Color, fill: Color, taps: Array = []) -> void:
	l.draw_style_box(_panel_sb, r)
	l.draw_string(font, Vector2(r.position.x, r.position.y + 32), title, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 24, title_col)
	var x0 := r.position.x + 40
	var sp := (r.size.x - 80) / (3.5 + STRIP_LEAD)
	var ly := r.position.y + 80
	var bx := func(beat: float) -> float: return x0 + (beat + STRIP_LEAD) * sp
	l.draw_line(Vector2(bx.call(-STRIP_LEAD) - 10, ly), Vector2(bx.call(0.0), ly), Color(INK, 0.15), 3.0)
	l.draw_line(Vector2(bx.call(0.0), ly), Vector2(bx.call(3.5) + 20, ly), Color(INK, 0.35), 3.0)
	var lb := -STRIP_LEAD
	while lb < 0.0:
		var whole := is_equal_approx(fposmod(lb, 1.0), 0.0)
		var txt := str(int(4.0 + lb) + 1) if whole else "&"
		l.draw_string(font, Vector2(bx.call(lb) - 30, ly - 18), txt, HORIZONTAL_ALIGNMENT_CENTER, 60, 18 if whole else 14, Color(INK, 0.3))
		if whole:
			l.draw_line(Vector2(bx.call(lb), ly - 6), Vector2(bx.call(lb), ly + 6), Color(INK, 0.25), 2.0)
		lb += 0.5
	for i in 4:
		l.draw_string(font, Vector2(bx.call(i) - 30, ly - 18), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 60, 22, Color(INK, 0.8))
		l.draw_line(Vector2(bx.call(i), ly - 8), Vector2(bx.call(i), ly + 8), Color(INK, 0.5), 3.0)
		l.draw_string(font, Vector2(bx.call(i + 0.5) - 30, ly - 18), "&", HORIZONTAL_ALIGNMENT_CENTER, 60, 16, Color(INK, 0.4))
	for i in pat.size():
		var c := Vector2(bx.call(pat[i]), ly)
		var m: int = marks[i] if i < marks.size() else 0
		if m == 1:
			l.draw_circle(c, 14.0, fill)
		else:
			l.draw_circle(c, 14.0, Color(1, 0.97, 0.88))
			if m == 2:
				_draw_x(l, c, 11.0, Color(0.85, 0.2, 0.15), 5.0)
		l.draw_arc(c, 14.0, 0.0, TAU, 32, INK, 3.0)
	for st in strays:
		_draw_x(l, Vector2(bx.call(st), ly), 9.0, Color(0.85, 0.2, 0.15), 4.0)
	for tp in taps:      # where each counted press actually landed (on the circle = perfect)
		var tx: float = bx.call(tp)
		l.draw_line(Vector2(tx, ly - 19), Vector2(tx, ly + 19), INK, 4.0)
	if head >= -STRIP_LEAD and head < 3.75:
		var hx: float = bx.call(head)
		l.draw_line(Vector2(hx, ly - 26), Vector2(hx, ly + 22), Color(0.85, 0.3, 0.2, 0.8), 4.0)


func _draw_x(l: Node2D, c: Vector2, s: float, col: Color, w: float) -> void:
	l.draw_line(c + Vector2(-s, -s), c + Vector2(s, s), col, w)
	l.draw_line(c + Vector2(-s, s), c + Vector2(s, -s), col, w)


func _tex(art_name: String) -> Texture2D:
	if not _art.has(art_name):
		var path: String = ART_DIR + ART[art_name][0]
		_art[art_name] = load(path) if ResourceLoader.exists(path) else null
	return _art[art_name]


## Art `art_name` fit into its box, the box's origin at `at`. No file yet: a
## labelled placeholder box.
func _draw_art(l: Node2D, art_name: String, at: Vector2, s: float) -> void:
	var box: Rect2 = ART[art_name][1]
	var tex := _tex(art_name)
	l.draw_set_transform(at, 0.0, Vector2(s, s))
	if tex:
		var k := minf(box.size.x / tex.get_width(), box.size.y / tex.get_height())
		var sz := Vector2(tex.get_width(), tex.get_height()) * k
		l.draw_texture_rect(tex, Rect2(box.get_center() - sz * 0.5, sz), false)
	else:
		_placeholder(l, box, art_name, 1.0, s)
	l.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A dashed box with the art's name in it, standing in for a drawing.
func _placeholder(l: Node2D, box: Rect2, label: String, alpha: float, s: float) -> void:
	var ink := Color(INK, 0.6 * alpha)
	var w := 3.0 / s
	l.draw_rect(box, Color(1, 1, 1, 0.55 * alpha))
	var c := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
	for i in 4:
		l.draw_dashed_line(c[i], c[(i + 1) % 4], ink, w, 10.0 / s)
	var fs := clampi(int(minf(box.size.y * 0.5, 16.0 / s)), 6, 200)
	l.draw_string(ThemeDB.fallback_font, Vector2(box.position.x, box.get_center().y + fs * 0.35), label,
		HORIZONTAL_ALIGNMENT_CENTER, box.size.x, fs, ink)
