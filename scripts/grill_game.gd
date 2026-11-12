extends Node2D
## "Grill Master" minigame. Cue and response: the grill tells you what it needs
## one bar ahead, in the rhythm you'll play -- the salt and pepper shakers hop
## with a shake-shake when it needs seasoning, and the patty bubbles up with a
## ding-ding when it's ready to flip (gold double-ding: onto the bun). You answer
## on the next bar with SPACE, in the same rhythm.
## Only the answers are graded. Clacks are presses; a flip (or the pop) is a HOLD:
## press on beat 1 to grab, let go on beat 2 to toss, and it lands on 3 by itself.
##
## You cook three whole burgers over the song. A clack pair seasons the patty: the
## salt shaker, then the pepper shaker, leans over the grill and shakes (miss one and it spills on
## the floor). The patty starts raw and browns a step with every flip you land
## (shaders/patty_cook.gdshader). A pop is the last flip of a burger: it lands the
## patty on your bun, the top bun drops on, and the burger hops over onto the
## picnic table -- then a fresh raw patty goes on the grill. Each burger is done
## when all of its flips (the pop included) landed. The ending is a close-up of
## all three, as cooked and as seasoned as you made them.
##
## All the art outside the tongs and grill is yours to draw: see ART below. Until
## a file exists, a labelled placeholder box stands in its place.
##
## Starts with a tutorial: explainer cards (how cues work, then each move) between
## practice rounds over a metronome -- first the tong clack, then the flip, each
## needing `practice_goal` clean answer bars. A rhythm strip at the top shows
## where the presses go and marks each one hit / missed / extra. S skips it.
##
## A flip only moves as far as you've got it: miss the grab, let go too soon or
## too late (or press when you shouldn't) and the patty drops back with a smoky puff.
##
## Chart: beatmaps/grill.tres -- cues { beat, cue: "tap" | "flip" | "pop",
## role: "call" | "answer" }. Flip and pop bars are cues on beats 1-2-3; for the
## answers, beat 1 is the press, beat 2 the release, and beat 3 plays itself.
##   Space / click  answer     S  skip practice     R  restart     Esc  menu

enum Phase { CARD, PRACTICE, SONG }
enum Card { WELCOME, CLACK, FLIP, READY }

const PERFECT := 0.075
const GOOD := 0.15
const MISS_TAIL := 0.03            ## seconds past the late edge of GOOD before it's a Miss
const VP := Vector2(1152, 648)
const INK := Color(0.2, 0.14, 0.12)
## Beats within a bar for each move (flip / pop: beats 1-2-3).
const PATTERN := {"tap": [2.5, 3.0], "flip": [0.0, 1.0, 2.0], "pop": [0.0, 1.0, 2.0]}
## Every sound in the game is a file you make, in SFX_DIR, named after its slot
## (.wav / .ogg / .mp3). A slot with no file plays a built-in placeholder.
## See audio/sfx/grill/README.md for what each one is.
const SFX_DIR := "res://audio/sfx/grill/"
const SFX_SLOTS := ["salt_cue", "pepper_cue", "flip_cue_1", "flip_cue_2", "pop_cue",
	"salt_shake", "pepper_shake", "tong", "flip", "whoosh", "land", "sizzle", "pop"]
## The flip animation is driven by the music clock, pinned to the bar: grab on
## beat 1 (the hit), top of the toss on beat 2 (the scrape), landing on beat 3
## (the sizzle), then back to rest. Values are frames of the "flip" animation.
const FLIP_GRAB := 7
const FLIP_TOP := 12
const FLIP_LAND := 19
const FLIP_END := 27
const TONG_TIP := Vector2(122, 385)   ## texture px where the tips meet in the "tap" frames
const FLIP_REACH := 0.5           ## beats into the reach before beat 1 (only if a flip starts early)
const FLIP_RETURN := 0.5           ## beats to go back to rest after the landing
const COOK_SHADER := preload("res://shaders/patty_cook.gdshader")
const COOK_FLIPS := 4              ## practice only: landed flips from raw to done (the song counts each burger's flips)
const CLOSEUP_IRIS := 0.3          ## seconds the zoom into the bun takes
const RESULTS_AFTER := 2.4         ## seconds of close-up before the results come up
## A finished burger, in seconds after its pop lands: the top bun drops on at
## SERVE_HOLD, it hops off the plate at SERVE_GO, and takes SERVE_FLY to get there.
const SERVE_HOLD := 0.3
const SERVE_GO := 1.0
const SERVE_FLY := 0.55
## A clack pair seasons the patty: clack 1 = salt, clack 2 = pepper.
const SEASONS := ["salt", "pepper"]
const SEASON_MS := 420.0           ## a seasoning: the shaker lifts toward the grill, shakes, and sets back down
const SEASON_REACH := Vector2(38, -30)   ## how far it leans out toward the grill (screen px)
const KNOCK_MS := 240.0            ## a knock: tongs on the shaker, then back to rest
const KNOCK_HOLD_MS := 50.0        ## ...staying on the shaker this long first
const FLY := 0.3                  ## seconds a pinch of salt / pepper takes to arc onto the patty
const PLAY_S := 0.36               ## scale of the burger art on the plates during play
## Art you draw, under res://art/grilling/: name -> [file, placeholder box].
## The burger layers (files in burger/) are all drawn on one BURGER-sized canvas,
## lined up as they stack -- export each Krita layer at full canvas size and the
## game just piles them up. The others are fit into their box (keeping their shape);
## the shakers' box is centred on the shaker.
const ART_DIR := "res://art/grilling/"
const BURGER := Vector2(600, 480)
const ART := {
	"table": ["closeup/table.png", Rect2(0, 0, 1152, 648)],
	"plate": ["burger/plate.png", Rect2(20, 384, 560, 86)],
	"bun_bottom": ["burger/bun_bottom.png", Rect2(110, 320, 380, 70)],
	"patty_raw": ["burger/patty_raw.png", Rect2(90, 262, 420, 66)],
	"patty_cooked": ["burger/patty_cooked.png", Rect2(90, 262, 420, 66)],
	"seasoning": ["burger/seasoning.png", Rect2(130, 262, 340, 26)],
	"bun_top": ["burger/bun_top.png", Rect2(110, 90, 380, 182)],
	"salt": ["season/salt.png", Rect2(-18, -24, 36, 48)],
	"pepper": ["season/pepper.png", Rect2(-18, -24, 36, 48)],
	"picnic_table": ["scene/table.png", Rect2(9, 193, 408, 257)],   # drawn into `table_rect` instead
}
const BUN_TOP_PIVOT := Vector2(300, 272)   ## burger canvas px the top bun squashes around (its bottom middle)
const PERFECT_COL := Color(1.0, 0.78, 0.15)
const GOOD_COL := Color(0.4, 0.75, 0.35)
const MISS_COL := Color(0.85, 0.2, 0.15)
## Separately exported layers (art/grilling/parts/): the patty alone and the bare
## tongs, so the patty can hop and the tongs can knock on their own.
const PARTS_DIR := "res://art/grilling/parts/"
## The cues. HOP_MS: how long a shaker / the patty hops. CUE_COL: the flip cue's
## glow; POP_COL: the pop's (that one lands on the bun).
const HOP_MS := 260.0
const CUE_COL := Color(1.0, 0.55, 0.15)
const POP_COL := Color(1.0, 0.8, 0.2)

@export var beatmap: Beatmap

@export_group("Layout")
@export var patty_pos := Vector2(605, 300)          ## your patty -- steam rises from here
@export var bun_pos := Vector2(320, 520)            ## your bun (the pop lands here)
@export var salt_pos := Vector2(300, 262)            ## your salt shaker (its middle), at the grill end of the picnic table
@export var pepper_pos := Vector2(334, 276)          ## your pepper shaker, next to it
@export var you_pos := Vector2(318, 250)            ## tip of the practice "YOU" arrow
## The picnic table (behind the tongs) your finished burgers are served onto --
## where it sits in your Krita scene.
@export var table_rect := Rect2(9, 193, 408, 257)
## Where each served burger sits on the table (bottom middle of its bun), in order.
@export var table_slots := PackedVector2Array([Vector2(110, 258), Vector2(158, 273), Vector2(206, 288)])
@export var served_scale := 0.12

@export_group("Practice round")
@export var practice: bool = true
## Clean answer bars needed in each practice step (claps, then flip).
@export var practice_goal: int = 2
@export var practice_metronome_db: float = -8.0

@onready var audio: AudioStreamPlayer = $AudioStreamPlayer
@onready var tongs: AnimatedSprite2D = $Stage/Tongs
var _parts := {}                   ## part name -> Array[Texture2D]

var _phase := Phase.SONG
var _practice_passed := false
var _song_stream: AudioStream
var _metronome: AudioStreamWAV

var _calls: Array = []             ## { beat, time, cue, part, sounded, shown } -- the cues (shaker hops, patty dings)
var _answers: Array = []           ## { beat, time, cue, part, bar, act: "press" | "release" } -- still to grade, in order
var _autos: Array = []             ## your flips' beat-3 landings: { beat, time, cue, bar, sounded, shown }
var _bars := {}                    ## bar id -> { left: int, missed: bool } (practice success)
var _next_cycle := 4.0             ## practice: beat the next call bar starts
var _cycle_start := -100.0        ## practice: beat the latest call bar starts (answer bar follows)
var _step := 0                     ## practice: 0 = tong claps, 1 = flip
var _step_ok := 0                  ## practice: clean answer bars in this step
var _cycles: Array = []            ## practice: { start, cue, cues: [], you: [], strays: [] } per cue+answer pair
var _card := Card.WELCOME
var _card_ms := 0                  ## when the card went up (ignore presses for a moment)
var _toast := {}                   ## { text, col, ms } -- short message under the rhythm strip
var banner := ""

var score := 0
var combo := 0
var best_combo := 0
var _tally := {"Perfect": 0, "Good": 0, "Miss": 0}
var _fx: Array = []                ## { kind, t0, pos } -- steam, pop, miss puff
var _served: Array = []            ## your finished burgers: { t (song time it landed), landed, raw, season }
var _burger_count := 1             ## burgers in the song (one per pop you answer)
var _cook_totals: Array = []       ## per burger: flips you get to answer (the pop included)
var _season_totals: Array = []     ## per burger: clacks you get to answer
var _seasoned_all := 0             ## clacks you landed over the whole song
var _finished := false
var _back_layer: Node2D            ## behind the tongs: the picnic table + served burgers

var _flips := {}                   ## AnimatedSprite2D -> song time of beat 1 of the flip it's doing
var _pflip := {}                   ## your flip in progress: { bar, hit: presses landed so far, fail }
var _fumble := {}                  ## your failed flip falling back: { t0, from: frame }
var _tongs_home: Vector2
var _stage: Node2D
var _stage_home: Vector2
var _held := false                 ## SPACE / mouse is down
var _press_ms := -10000            ## last press (the tongs dip)
var _shake_ms := -10000            ## last good hit (the stage jolts)
var _combo_ms := -10000            ## combo went up (the counter pulses)
var _cooked := 0                   ## flips you've landed -> how browned your patty is
var _raw := 1.0                    ## shown rawness (eases toward the target)
var _hop := {}                     ## "salt" / "pepper" / "patty" -> ticks ms it last hopped for a cue
var _flip_due := ""                ## "flip" / "pop" while the patty is waiting to be flipped, else ""
var _closeup_ms := -1              ## when the burger close-up started (-1: not yet)
var _seasoned := 0                 ## clacks you landed on this burger (each one salts or peppers it)
var _season_total := 0             ## clacks you get to answer in the song
var _jolt := {}                    ## "salt" / "pepper" -> [ticks ms, shook (true) or wobbled on a miss (false)]
var _art := {}                     ## art name -> Texture2D, or null when not drawn yet
var _knocks := {}                  ## tongs -> { ms, d: screen px from the tips' rest spot to the shaker }
var _tip_home := {}                ## tongs -> where its tips are at rest (screen px)
var _knock_patty: Sprite2D         ## your patty on its own, shown while your tongs knock
var _knock_tongs: Sprite2D         ## your bare tongs, which do the knocking
var _pop := {}                     ## the patty flying onto the bun: { t0, t1, frame, finish, done, hide_until } (visual times)
var _pop_back: Sprite2D            ## your tongs without the patty (back arm), while it flies
var _pop_front: Sprite2D           ## ...and the front arm
var _pop_patty: Sprite2D           ## the flying patty itself (above the plate)
var _patty_box := {}               ## flip_patty frame -> where the patty is in that frame (texture px)
var _fx_layer: Node2D
var _sfx: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _panel_sb: StyleBoxFlat


func _ready() -> void:
	_fx_layer = Node2D.new()          # effects + HUD above the grill art
	add_child(_fx_layer)
	_fx_layer.draw.connect(_draw_fx)
	_back_layer = Node2D.new()        # the table goes behind the grill + tongs
	add_child(_back_layer)
	move_child(_back_layer, $Stage.get_index())
	_back_layer.draw.connect(_draw_back)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_panel_sb = StyleBoxFlat.new()
	_panel_sb.bg_color = Color(1, 0.97, 0.88)
	_panel_sb.set_corner_radius_all(18)
	_panel_sb.set_border_width_all(4)
	_panel_sb.border_color = INK
	for part in ["flip_patty", "tap_tongs"]:
		_parts[part] = [load("%s%s/%s_00.png" % [PARTS_DIR, part, part])]
	_tongs_home = tongs.position
	_stage = tongs.get_parent()
	_stage_home = _stage.position
	var cook := ShaderMaterial.new()          # your tongs' frames include the patty
	cook.shader = COOK_SHADER
	tongs.material = cook
	# your tongs' frames have the patty drawn in, so for a knock (or the patty's
	# cue hop) the two come apart: the patty part and the bare tongs part
	var at := tongs.get_index() + 1
	for n in ["KnockPatty", "KnockTongs"]:
		var s := Sprite2D.new()
		s.name = n
		s.centered = false
		s.position = _tongs_home
		s.visible = false
		s.texture = (_parts["flip_patty"] if n == "KnockPatty" else _parts["tap_tongs"])[0]
		_stage.add_child(s)
		_stage.move_child(s, at)
		at += 1
		if n == "KnockPatty":
			s.material = cook
			_knock_patty = s
		else:
			_knock_tongs = s
	_tip_home = {tongs: _tip(tongs)}
	# the pop: the patty leaves the tongs at the toss and flies onto your bun, so
	# the tongs are shown without it (back + front arm) and the patty on its own
	for part in ["flip_back", "flip_front", "flip_patty"]:
		var frames: Array = []
		for i in FLIP_END + 1:
			frames.append(load("%s%s/%s_%02d.png" % [PARTS_DIR, part, part, i]))
		_parts[part] = frames
	for n in ["PopBack", "PopFront"]:
		var s := Sprite2D.new()
		s.name = n
		s.centered = false
		s.visible = false
		_stage.add_child(s)
		_stage.move_child(s, at)
		at += 1
		if n == "PopBack":
			_pop_back = s
		else:
			_pop_front = s
	_pop_patty = Sprite2D.new()
	_pop_patty.name = "PopPatty"
	_pop_patty.centered = false
	_pop_patty.visible = false
	_pop_patty.material = cook
	_fx_layer.add_child(_pop_patty)

	_song_stream = audio.stream
	Conductor.stream_player = audio
	if beatmap:
		Conductor.bpm = beatmap.bpm
		Conductor.first_beat_offset = beatmap.first_beat_offset
		Conductor.video_offset = beatmap.video_offset
		Conductor.input_offset = Settings.input_offset(beatmap.input_offset)
	Conductor.song_finished.connect(_on_song_finished)
	_load_sounds()
	_restart()


## Your sound files, with a built-in placeholder for any slot you haven't made yet.
func _load_sounds() -> void:
	var missing: Array = []
	for slot: String in SFX_SLOTS:
		var s := load_sound(SFX_DIR, slot)
		if s == null:
			missing.append(slot)
			s = _placeholder_sound(slot)
		if s:
			_sfx[slot] = s
	if not missing.is_empty():
		print("[grill] placeholder sounds still in use (make %s<slot>.wav): %s" % [SFX_DIR, ", ".join(missing)])


## `dir`/`slot`.wav, .ogg or .mp3 -- whichever exists -- or null.
static func load_sound(dir: String, slot: String) -> AudioStream:
	for ext in ["wav", "ogg", "mp3"]:
		var path := "%s%s.%s" % [dir, slot, ext]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null


## Stand-ins until you make the real thing: a bell for "ready to flip", a rattle
## for "season me", noise for the whoosh and the landing. Null = silent.
func _placeholder_sound(slot: String) -> AudioStream:
	match slot:
		"salt_cue": return _synth_shake(0.75, 3)
		"pepper_cue": return _synth_shake(0.35, 4)
		"flip_cue_1": return _synth_ding([1318.5], 0.45)
		"flip_cue_2": return _synth_ding([1760.0], 0.45)
		"pop_cue": return _synth_ding([1568.0, 2093.0], 0.5)
		"whoosh": return _synth_whoosh()
		"salt_shake": return _synth_shake(0.75, 3)
		"pepper_shake": return _synth_shake(0.35, 4)
		"land": return _synth_sear()
	return null


## Conductor is an autoload and outlives this scene -- stop it before our
## AudioStreamPlayer is freed, or its _process would poke a dead node.
func _exit_tree() -> void:
	Conductor.song_finished.disconnect(_on_song_finished)
	Conductor.stop()
	Conductor.stream_player = null


func _restart() -> void:
	if practice and not _practice_passed:
		_show_card(Card.WELCOME)
	else:
		_start_song()


func _reset_round() -> void:
	_calls.clear()
	_answers.clear()
	_bars.clear()
	_cycles.clear()
	_fx.clear()
	_served.clear()
	_burger_count = 1
	_cook_totals.clear()
	_season_totals.clear()
	_seasoned_all = 0
	_finished = false
	banner = ""
	_toast = {}
	score = 0
	combo = 0
	best_combo = 0
	_tally = {"Perfect": 0, "Good": 0, "Miss": 0}
	_flips.clear()
	_pflip = {}
	_fumble = {}
	_pop = {}
	_autos.clear()
	_held = false
	_cooked = 0
	_raw = 1.0
	_hop.clear()
	_flip_due = ""
	_closeup_ms = -1
	_seasoned = 0
	_season_total = 0
	_jolt.clear()
	_knocks.clear()
	tongs.position = _tongs_home
	_stage.position = _stage_home
	tongs.play(&"flip")
	tongs.stop()
	tongs.frame = 0


## Stop everything and put up an explainer card; SPACE moves on.
func _show_card(card: Card) -> void:
	Conductor.stop()
	_reset_round()
	_phase = Phase.CARD
	_card = card
	_card_ms = Time.get_ticks_msec()


func _advance_card() -> void:
	if Time.get_ticks_msec() - _card_ms < 500:   # a press left over from the last bar
		return
	match _card:
		Card.WELCOME: _show_card(Card.CLACK)
		Card.CLACK: _start_practice(0)
		Card.FLIP: _start_practice(1)
		Card.READY:
			_practice_passed = true
			_start_song()


func _start_practice(step: int) -> void:
	_reset_round()
	_phase = Phase.PRACTICE
	_step = step
	_step_ok = 0
	_next_cycle = 4.0            # one bar of clicks first
	_cycle_start = -100.0
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
	# count what goes into each burger: a pop finishes one and starts the next
	_cook_totals = [0]
	_season_totals = [0]
	var pops := 0
	for c in (beatmap.compiled(Conductor) if beatmap else []):
		var cue := {"beat": c["beat"], "time": c["time"], "cue": c["cue"],
			"part": _part(c["cue"], c["beat"]), "bar": int(floor(c["beat"] / 4.0))}
		var role: String = c.get("role", "answer")
		if role == "answer":
			if cue["cue"] == "tap":
				_season_total += 1
				_season_totals[-1] += 1
			elif cue["part"] == 0:
				_cook_totals[-1] += 1
			elif cue["cue"] == "pop" and cue["part"] == 2:
				pops += 1
				_cook_totals.append(0)
				_season_totals.append(0)
		if role == "call":             # a cue: the shakers hop / the patty dings
			cue["sounded"] = false
			cue["shown"] = false
			_calls.append(cue)
		else:
			_add_answer(cue)
	_burger_count = maxi(1, pops)
	Conductor.play()


## How many flips (or clacks) burger `i` has in the song; practice: COOK_FLIPS.
func _total(totals: Array, i: int, fallback: int) -> int:
	return maxi(1, totals[i]) if i < totals.size() else fallback


## A pop's landing finishes a burger (`landed`: the patty made it onto the bun).
## It goes on the list with how cooked and seasoned it got, and a fresh raw
## patty goes on the grill. Your last one starts the close-up.
func _finish_burger(landed: bool) -> void:
	var now := Conductor.song_position
	var i := _served.size()
	_served.append({"t": now, "landed": landed,
		"raw": 1.0 - clampf(float(_cooked) / _total(_cook_totals, i, COOK_FLIPS), 0.0, 1.0),
		"season": clampf(float(_seasoned) / _total(_season_totals, i, 1), 0.0, 1.0)})
	_seasoned_all += _seasoned
	_seasoned = 0
	_cooked = 0
	_raw = 1.0
	_fx.append({"kind": "steam", "t0": now, "pos": patty_pos})
	if _phase == Phase.SONG and _served.size() >= _burger_count:
		_closeup_ms = Time.get_ticks_msec() + 350   # let the landing show for a moment


## Queue one of your cues: a press, a release (beat 2 of a flip), or -- beat 3 of
## a flip -- the landing, which isn't graded and plays itself if the toss worked.
func _add_answer(a: Dictionary) -> void:
	if a["cue"] != "tap" and a["part"] == 2:
		a["sounded"] = false
		a["shown"] = false
		_autos.append(a)
		return
	a["act"] = "release" if a["cue"] != "tap" and a["part"] == 1 else "press"
	_answers.append(a)


## Which press of its bar a cue is (0-based), from the bar's pattern.
func _part(cue: String, beat: float) -> int:
	if cue == "tap":   # a clack pair is an "and" then the next beat -- not always on 3-and-4 in the song
		return 0 if is_equal_approx(fposmod(beat, 1.0), 0.5) else 1
	return maxi(0, (PATTERN.get(cue, [0.0]) as Array).find(fposmod(beat, 4.0)))


func _on_song_finished() -> void:
	if _phase == Phase.PRACTICE:
		# keep practising: the click track starts over, and so do the bars
		_calls.clear()
		_answers.clear()
		_bars.clear()
		_cycles.clear()
		_fx.clear()        # the clock goes back to 0 -- old effects would get negative ages
		_flips.clear()
		_pflip = {}
		_autos.clear()
		_next_cycle = 4.0
		_cycle_start = -100.0
		Conductor.play()
	elif _phase == Phase.SONG:
		_finished = true


# --- practice ------------------------------------------------------------------

## Queue the next call bar + answer bar half a beat before it starts.
func _schedule_practice() -> void:
	if _phase != Phase.PRACTICE or Conductor.song_position_in_beats < _next_cycle - 0.5:
		return
	var cue: String = ["tap", "flip"][_step]
	var bar := int(_next_cycle / 4.0)
	var n := (PATTERN[cue] as Array).size()
	var cyc := {"start": _next_cycle, "cue": cue, "cues": [], "you": [], "strays": [], "taps": []}
	cyc["cues"].resize(n)
	cyc["cues"].fill(0)
	cyc["you"].resize(n)
	cyc["you"].fill(0)
	_cycles.append(cyc)
	if _cycles.size() > 3:
		_cycles.pop_front()
	for off in PATTERN[cue]:
		var cb: float = _next_cycle + off
		var ab: float = _next_cycle + 4.0 + off
		_calls.append({"beat": cb, "time": Conductor.time_of_beat(cb), "cue": cue,
			"part": _part(cue, cb), "sounded": false, "shown": false, "cycle": cyc})
		_add_answer({"beat": ab, "time": Conductor.time_of_beat(ab), "cue": cue,
			"part": _part(cue, ab), "bar": bar + 1, "cycle": cyc})
	_bars[bar + 1] = {"left": n if cue == "tap" else 2, "missed": false}   # a flip grades the press + the release
	_cycle_start = _next_cycle
	_next_cycle += 8.0


## One press of a practice answer bar has been graded.
func _bar_result(bar: int, missed: bool) -> void:
	if _phase != Phase.PRACTICE or not _bars.has(bar):
		return
	var b: Dictionary = _bars[bar]
	b["left"] -= 1
	b["missed"] = b["missed"] or missed


## Judge answer bars once every press is graded and the bar is nearly over (so
## an extra press after the last one still counts against it).
func _judge_bars() -> void:
	var beat := Conductor.song_position_in_beats
	for bar: int in _bars.keys():
		var b: Dictionary = _bars[bar]
		if b["left"] > 0 or beat < bar * 4.0 + 3.5:
			continue
		_bars.erase(bar)
		if b["missed"]:
			_say("Not quite -- listen to the cue and try again!", Color(0.85, 0.25, 0.2))
			continue
		_step_ok += 1
		if _step_ok < practice_goal:
			_say("Nice! Do it once more.", Color(0.25, 0.55, 0.25))
			continue
		_show_card(Card.FLIP if _step == 0 else Card.READY)
		return


func _say(text: String, col: Color) -> void:
	_toast = {"text": text, "col": col, "ms": Time.get_ticks_msec()}


## The practice cycle being played right now (or null in the count-in).
func _current_cycle() -> Variant:
	var b := Conductor.visual_position / Conductor.seconds_per_beat
	for c in _cycles:
		if b >= c["start"] and b < c["start"] + 8.0:
			return c
	return null


# --- per frame -------------------------------------------------------------------

func _process(_dt: float) -> void:
	var now: float = Conductor.song_position
	var vis: float = Conductor.visual_position
	var latency := AudioServer.get_output_latency()
	if _phase == Phase.PRACTICE:
		_judge_bars()
		_schedule_practice()

	for c in _calls:
		# the cue's sound, fired output-latency early so it's heard on the beat
		if not c["sounded"] and now >= c["time"] - latency:
			c["sounded"] = true
			_cue_sound(c["cue"], c["part"])
		if not c["shown"] and vis >= c["time"]:
			c["shown"] = true
			_cue_show(c["cue"], c["part"])
			if c.has("cycle"):
				c["cycle"]["cues"][c["part"]] = 1
	_calls = _calls.filter(func(c): return not (c["sounded"] and c["shown"]))
	_land_autos(now, vis, latency)
	_drive_flips(vis)
	_drive_fumble(now)
	_drive_feel(_dt)
	_drive_pop(Conductor.visual_position)

	# an answer nobody pressed for -> Miss
	while not _answers.is_empty() and now > _answers[0]["time"] + Conductor.input_offset + GOOD + MISS_TAIL:
		var a: Dictionary = _answers.pop_front()
		_grade(a, "Miss")
	_fx = _fx.filter(func(f): return now - f["t0"] >= -0.05 and now - f["t0"] < 1.2)
	_fx_layer.queue_redraw()
	_back_layer.queue_redraw()


## Beat 3 of your flips: if the grab and the toss both landed, the patty comes
## down with a sizzle (or onto the bun, for the pop) -- and the pop starts the close-up.
func _land_autos(now: float, vis: float, latency: float) -> void:
	for a in _autos:
		var ok: bool = _pflip.get("bar", -1) == a["bar"] and _pflip.get("hit", 0) == 2 and not _pflip.get("fail", true)
		if not a["sounded"] and now >= a["time"] - latency:
			a["sounded"] = true
			if ok or a["cue"] == "pop":   # the pop always lands on the bun
				_sound(a["cue"], 2)
		if not a["shown"] and vis >= a["time"]:
			a["shown"] = true
			if ok:
				_pflip["hit"] = 3
				_act(a["cue"], 2, a["beat"])
				if a.has("cycle"):
					a["cycle"]["you"][2] = 1
			elif a["cue"] == "pop":
				# the pop fell apart -- the patty still goes on the bun, just less cooked
				# (no patty is ever lost; misses only leave it rawer)
				_flips.erase(tongs)
				_fumble = {}
				_start_pop(vis, vis + 0.35, true, vis + 0.35)
	_autos = _autos.filter(func(a): return not (a["sounded"] and a["shown"]))


## The little things that make presses feel physical: the tongs dip when you
## press, tremble while you hold a patty, the stage jolts on a hit, and the
## patty browns smoothly toward how cooked it is.
func _drive_feel(dt: float) -> void:
	var ms := Time.get_ticks_msec()
	var holding: bool = _flips.has(tongs) and _pflip.get("hit", 0) > 0   # is the patty in the tongs?
	var dip := 1.0 - clampf((ms - _press_ms) / 140.0, 0.0, 1.0)
	var dip_off := Vector2(-4.0, 9.0) * dip * dip
	if _fumble.is_empty():
		var off := Vector2.ZERO
		if holding:
			off = dip_off   # the patty's in the tongs: it dips with them
			if _held and _pflip.get("hit", 0) == 1 and not _pflip.get("fail", true):
				off += Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))   # straining to hold it up
		tongs.position = _tongs_home + off
	# a knock: the bare tongs swing onto the shaker while the patty stays on the grill;
	# a flip cue: the patty hops up off the grill on its own; a press that isn't
	# a flip: only the bare tongs dip -- the patty stays put on the grill
	var knock := _knock_off(tongs)
	var hop := Vector2(0, -26.0 * _hop_amount("patty")) / _stage.scale.y
	var split := (knock != Vector2.ZERO or hop != Vector2.ZERO or dip > 0.0) \
		and _fumble.is_empty() and not _flips.has(tongs)
	tongs.visible = not split
	_knock_patty.visible = split
	_knock_tongs.visible = split
	_knock_tongs.position = _tongs_home + knock + (dip_off if split else Vector2.ZERO)
	_knock_patty.position = _tongs_home + hop
	var sk := 1.0 - clampf((ms - _shake_ms) / 160.0, 0.0, 1.0)
	_stage.position = _stage_home + Vector2(sin(ms * 0.09) * 4.0, cos(ms * 0.11) * 3.0) * sk
	var k := 1.0 - exp(-dt * 5.0)
	_raw = lerpf(_raw, 1.0 - clampf(float(_cooked) / _total(_cook_totals, _served.size(), COOK_FLIPS), 0.0, 1.0), k)
	(tongs.material as ShaderMaterial).set_shader_parameter("raw", _raw)


## Send the patty flying from the grill onto your bun, from visual time t0 to t1,
## flipping over on the way. `finish`: finish the burger when it lands (a missed
## pop -- a landed one is finished by its beat 3). The tongs show without the
## patty until `hide_until`.
func _start_pop(t0: float, t1: float, finish: bool, hide_until: float) -> void:
	_pop = {"t0": t0, "t1": maxf(t1, t0 + 0.05), "frame": clampi(tongs.frame, 0, FLIP_END),
		"finish": finish, "done": false, "hide_until": hide_until}


## Where the patty is in a flip_patty frame (texture px), worked out once per frame.
func _patty_rect(frame: int) -> Rect2:
	if not _patty_box.has(frame):
		var img: Image = (_parts["flip_patty"][frame] as Texture2D).get_image()
		_patty_box[frame] = Rect2(img.get_used_rect()) if img else Rect2(0, 0, 120, 60)
	return _patty_box[frame]


func _drive_pop(vis: float) -> void:
	if _pop.is_empty():
		_pop_back.visible = false
		_pop_front.visible = false
		_pop_patty.visible = false
		return
	var t0: float = _pop["t0"]
	var t1: float = _pop["t1"]
	# the patty: an arc from where it was in the tongs to the top of your bun,
	# flipping over (squashed through edge-on) and growing to the plate's size
	var flying := vis < t1
	_pop_patty.visible = flying
	if flying:
		var k := clampf((vis - t0) / (t1 - t0), 0.0, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		var f: int = _pop["frame"]
		var box := _patty_rect(f)
		var mid := box.get_center()
		var from: Vector2 = _stage.get_global_transform() * (tongs.position + mid)
		var to: Vector2 = bun_pos + Vector2(0, 60) + Vector2(0, -185.0) * PLAY_S
		var tex: Texture2D = _parts["flip_patty"][f]
		var w := maxf(1.0, box.size.x)
		var grow := lerpf(1.0, 420.0 * PLAY_S / (w * _stage.scale.x), e)
		_pop_patty.texture = tex
		_pop_patty.offset = -mid
		_pop_patty.position = from.lerp(to, e) + Vector2(0, -150.0 * sin(PI * k))
		_pop_patty.scale = _stage.scale * Vector2(grow, grow * cos(PI * k))
	elif _pop["finish"] and not _pop["done"]:
		_pop["done"] = true
		_fx.append({"kind": "pop", "t0": Conductor.song_position, "pos": bun_pos})
		_finish_burger(true)
	# the tongs, without the patty, while it's away
	var hide := vis < float(_pop["hide_until"])
	if hide:
		tongs.visible = false
		_knock_patty.visible = false
		var mid_flip := _flips.has(tongs)
		_knock_tongs.visible = not mid_flip
		_knock_tongs.position = _tongs_home
		_pop_back.visible = mid_flip
		_pop_front.visible = mid_flip
		if mid_flip:
			_pop_back.texture = _parts["flip_back"][tongs.frame]
			_pop_front.texture = _parts["flip_front"][tongs.frame]
			_pop_back.position = tongs.position
			_pop_front.position = tongs.position
	else:
		_pop_back.visible = false
		_pop_front.visible = false
	if not flying and not hide and (not _pop["finish"] or _pop["done"]):
		_pop = {}


## 0..1..0 over a cue hop of `what` ("salt", "pepper", "patty"); 0 when not hopping.
func _hop_amount(what: String) -> float:
	var e := (Time.get_ticks_msec() - int(_hop.get(what, -100000))) / HOP_MS
	return sin(PI * e) if e < 1.0 else 0.0


## A cue's look, on its beat. Seasoning: that shaker hops (salt on the "and",
## pepper on the beat after). Flip: the patty hops and bubbles on beats 1 and 2
## (gold for the pop), and a "!" stays over it until you grab it.
func _cue_show(cue: String, part: int) -> void:
	var t := Conductor.song_position
	if cue == "tap":
		var season: String = SEASONS[clampi(part, 0, 1)]
		_hop[season] = Time.get_ticks_msec()
		_fx.append({"kind": "cue_ring", "t0": t, "pos": _shaker_at(season), "col": CUE_COL})
		return
	if part > 1:
		return
	_hop["patty"] = Time.get_ticks_msec()
	_flip_due = cue
	var col := POP_COL if cue == "pop" else CUE_COL
	_fx.append({"kind": "bubbles", "t0": t, "pos": patty_pos, "seed": randi(), "col": col})
	_fx.append({"kind": "cue_ring", "t0": t, "pos": patty_pos + Vector2(0, 4), "col": col})
	if cue == "pop":   # this one goes on the bun: the plate lights up too
		_fx.append({"kind": "cue_ring", "t0": t, "pos": bun_pos + Vector2(0, 30), "col": col})


## A cue's sound: a shaker rattle (salt higher, pepper lower), or a bell ding on
## beats 1 and 2 of a flip (the pop: a brighter double ding).
func _cue_sound(cue: String, part: int) -> void:
	if cue == "tap":
		_play_sfx("salt_cue" if part == 0 else "pepper_cue", -4.0)
	elif part == 0:
		_play_sfx("pop_cue" if cue == "pop" else "flip_cue_1", -6.0)
	elif part == 1:
		_play_sfx("pop_cue" if cue == "pop" else "flip_cue_2", -6.0)


func _unhandled_input(e: InputEvent) -> void:
	var button: bool = (e is InputEventKey and not e.echo and e.keycode == KEY_SPACE) \
		or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT)
	if button:
		if _phase == Phase.CARD:
			if e.pressed:
				_advance_card()
		elif e.pressed:
			_press()
		else:
			_release()
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_S:
				if _phase == Phase.PRACTICE or _phase == Phase.CARD:
					_practice_passed = true
					_start_song()
			KEY_R:
				_restart()
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://MainMenu.tscn")


func _press() -> void:
	_held = true
	if _finished or _closeup_ms >= 0:
		return
	_press_ms = Time.get_ticks_msec()
	if not _answers.is_empty() and _answers[0]["act"] == "press":
		var c: Dictionary = _answers[0]
		var err: float = Conductor.timing_error(c["beat"])
		if absf(err) <= GOOD:
			_answers.pop_front()
			_hit(c, err)
			return
	if _phase == Phase.PRACTICE:
		_stray_press()
	# nothing to answer -- the tongs just dip (the sound always plays, even when spamming)
	_sound("tap", 0)


## Letting go. Only means something while you're holding a patty up: on beat 2
## it's the toss; any other time the patty slips out and drops.
func _release() -> void:
	if not _held:
		return
	_held = false
	if _finished or _closeup_ms >= 0 or _answers.is_empty() or _answers[0]["act"] != "release":
		return
	var c: Dictionary = _answers[0]
	if _pflip.get("bar", -1) != c["bar"] or _pflip.get("hit", 0) != 1 or _pflip.get("fail", true):
		return
	_answers.pop_front()
	var err: float = Conductor.timing_error(c["beat"])
	if absf(err) <= GOOD:
		_hit(c, err)
		return
	if _phase == Phase.PRACTICE:
		_say("Let go too soon! Hold it until beat 2.", MISS_COL)
	_grade(c, "Miss")


## A press or release that landed in the window.
func _hit(c: Dictionary, err: float) -> void:
	if c.has("cycle"):   # practice: show where it landed, and if it was off
		c["cycle"]["taps"].append(c["beat"] - c["cycle"]["start"] - 4.0 + err / Conductor.seconds_per_beat)
		if absf(err) > PERFECT:
			_say("A little early!" if err < 0.0 else "A little late!", Color(0.7, 0.45, 0.0))
	_grade(c, "Perfect" if absf(err) <= PERFECT else "Good")


## Practice: a press that isn't on any of your beats. During the cue bar it's
## a gentle "wait"; during your bar it's a mistake (marked on the strip).
func _stray_press() -> void:
	var cyc: Variant = _current_cycle()
	if cyc == null:
		_say("Wait -- that was the cue! Answer it next bar.", Color(0.25, 0.4, 0.75))
		return
	var b: float = (Conductor.live_position() - Conductor.input_offset - Conductor.first_beat_offset) \
		/ Conductor.seconds_per_beat - cyc["start"]
	if b < 4.0:
		_say("Wait -- that was the cue! Answer it next bar.", Color(0.25, 0.4, 0.75))
		return
	if b >= 8.0:
		return
	cyc["strays"].append(b - 4.0)
	var bar := int(cyc["start"] / 4.0) + 1
	if _bars.has(bar):
		_bars[bar]["missed"] = true
	_fx.append({"kind": "x", "t0": Conductor.song_position, "pos": you_pos})
	if cyc["cue"] != "tap":
		_say("Extra press! Just HOLD on 1, let go on 2.", Color(0.85, 0.25, 0.2))
		if not _pflip.is_empty() and not _pflip["fail"]:
			_pflip["fail"] = true
			_fail_flip()
	else:
		_say("Extra press! Just two shakes: salt, then pepper.", Color(0.85, 0.25, 0.2))


func _grade(c: Dictionary, grade: String) -> void:
	_bar_result(c.get("bar", -1), grade == "Miss")
	if c.has("cycle"):
		c["cycle"]["you"][c["part"]] = 2 if grade == "Miss" else 1
	if _phase == Phase.SONG:
		_tally[grade] += 1
		if grade == "Miss":
			combo = 0
		else:
			combo += 1
			_combo_ms = Time.get_ticks_msec()
			best_combo = maxi(best_combo, combo)
			score += 100 if grade == "Perfect" else 50
	var now := Conductor.song_position
	var col: Color = {"Perfect": PERFECT_COL, "Good": GOOD_COL, "Miss": MISS_COL}[grade]
	_fx.append({"kind": "judge", "t0": now, "pos": you_pos + Vector2(0, -70), "text": grade.to_upper() + ("!" if grade == "Perfect" else ""), "col": col})
	if grade != "Miss":
		_shake_ms = Time.get_ticks_msec() if grade == "Perfect" else _shake_ms
		_fx.append({"kind": "sparks", "t0": now, "pos": patty_pos + Vector2(0, 10),
			"seed": randi(), "n": 9 if grade == "Perfect" else 5})
	_player_move(c, grade)


## What your tongs do for a graded answer. A flip/pop only goes as far as the
## presses you've landed in a row: it waits at each step for the next press,
## and a miss drops the patty back.
func _player_move(c: Dictionary, grade: String) -> void:
	var hit := grade != "Miss"
	var practising := _phase != Phase.SONG
	if c["cue"] == "tap":
		if hit:
			_play_sfx("salt_shake" if c["part"] == 0 else "pepper_shake", 0.0)   # sounds the instant it lands
			_act("tap", c["part"], c["beat"])
		else:
			# missed: that shaker spills on the floor instead of the patty
			var season: String = SEASONS[clampi(c["part"], 0, 1)]
			_fx.append({"kind": "x", "t0": Conductor.song_position, "pos": you_pos})
			_fx.append({"kind": "spill", "t0": Conductor.song_position, "pos": _shaker_at(season),
				"season": season, "seed": randi()})
			_jolt[season] = [Time.get_ticks_msec(), false]   # a guilty wobble, not a shake
			if practising:
				_say("Missed! The %s went on the floor." % season, MISS_COL)
		return
	var part: int = c["part"]
	if part == 0:
		_flip_due = ""      # the grab came (or went): the "!" goes away
	if part == 0 or _pflip.get("bar", -1) != c["bar"]:
		_pflip = {"bar": c["bar"], "hit": 0, "fail": false}
	if hit and not _pflip["fail"] and _pflip["hit"] == part:
		_pflip["hit"] += 1
		if c["cue"] == "pop" and part == 1:
			# the toss of a pop: the patty leaves the tongs and flies onto the bun,
			# landing on beat 3 (where the burger is finished)
			_start_pop(Conductor.visual_position, Conductor.time_of_beat(c["beat"] + 1.0), false,
				Conductor.time_of_beat(c["beat"] + 1.0 + FLIP_RETURN))
		_sound(c["cue"], part)
		_act(c["cue"], part, c["beat"])
	elif hit:
		# on time, but the flip already fell apart -- just the sound
		_sound("tap", 0)
	elif not _pflip["fail"]:
		_pflip["fail"] = true
		_fail_flip()
		if practising and part == 1 and _toast.get("ms", 0) < Time.get_ticks_msec() - 100:
			_say("Let go on beat 2 -- don't hang on!", MISS_COL)
	if part == 0 and not hit:
		_drop_release(c["bar"])
		if practising:
			_say("Missed the grab! Press and HOLD on beat 1.", MISS_COL)


## The grab was missed, so there's nothing to let go of: take the release off
## the list without a second Miss (it still marks the practice bar as missed).
func _drop_release(bar: int) -> void:
	for i in _answers.size():
		var a: Dictionary = _answers[i]
		if a["bar"] == bar and a["act"] == "release":
			_answers.remove_at(i)
			_bar_result(bar, true)
			if a.has("cycle"):
				a["cycle"]["you"][1] = 2
			return


## Your flip fails: the patty drops back onto the grill, tongs shake, smoke.
func _fail_flip() -> void:
	var from := tongs.frame if tongs.animation == &"flip" else 0
	_flips.erase(tongs)
	_fumble = {"t0": Conductor.song_position, "from": from}
	_fx.append({"kind": "miss", "t0": Conductor.song_position, "pos": patty_pos})
	_fx.append({"kind": "x", "t0": Conductor.song_position, "pos": you_pos})


func _drive_fumble(now: float) -> void:
	if _fumble.is_empty():
		return
	var k := clampf((now - _fumble["t0"]) / 0.35, 0.0, 1.0)
	if tongs.animation != &"flip":
		tongs.animation = &"flip"
	tongs.stop()
	tongs.frame = int(lerpf(_fumble["from"], 0.0, k))
	tongs.position = _tongs_home + Vector2(sin(k * 40.0) * 10.0 * (1.0 - k), 0.0)
	if k >= 1.0:
		tongs.position = _tongs_home
		_fumble = {}


## Animate one press of a move on your tongs.
func _act(cue: String, part: int, beat: float) -> void:
	var t := Conductor.song_position
	match cue:
		"tap":
			# each clack seasons the patty -- salt, then pepper: the shaker leans out
			# toward the grill as if someone's shaking it, and a pinch arcs onto the patty
			var season: String = SEASONS[clampi(part, 0, 1)]
			_jolt[season] = [Time.get_ticks_msec(), true]
			_fx.append({"kind": "pinch", "t0": t, "pos": _shaker_at(season) + SEASON_REACH + Vector2(12, -22),
				"to": patty_pos + Vector2(0, 6), "season": season, "seed": randi()})
			if _phase == Phase.SONG:
				_seasoned += 1
		"flip", "pop":
			# any press of the bar starts (or keeps) the flip, pinned to that bar's beat 1
			var beat1 := Conductor.time_of_beat(beat - float(part))
			if not is_equal_approx(_flips.get(tongs, -1.0), beat1):
				_flips[tongs] = beat1
			if part != 2:
				return
			_cooked += 1
			_shake_ms = Time.get_ticks_msec()
			if cue == "pop":                            # beat 3 of the pop bar: the last flip, onto the bun
				_fx.append({"kind": "pop", "t0": t, "pos": bun_pos})
				_finish_burger(true)
			else:                                       # beat 3: lands with a sizzle, a bit more done
				_fx.append({"kind": "steam", "t0": t, "pos": patty_pos})
				_fx.append({"kind": "sparks", "t0": t, "pos": patty_pos + Vector2(0, 10), "seed": randi(), "n": 12})



## How far a knock has a set of tongs moved right now (Stage px; zero when not knocking).
func _knock_off(who: AnimatedSprite2D) -> Vector2:
	if not _knocks.has(who):
		return Vector2.ZERO
	var e := float(Time.get_ticks_msec() - int(_knocks[who]["ms"]))
	if e >= KNOCK_MS:
		return Vector2.ZERO
	var a := 1.0 if e < KNOCK_HOLD_MS else pow(1.0 - (e - KNOCK_HOLD_MS) / (KNOCK_MS - KNOCK_HOLD_MS), 2.0)
	return (_knocks[who]["d"] as Vector2) * a / _stage.scale.x


## Where the tong tips meet, on screen.
func _tip(who: AnimatedSprite2D) -> Vector2:
	return who.get_global_transform() * TONG_TIP


## Set each flipping tongs' frame from the music clock (see FLIP_GRAB etc.).
func _drive_flips(vis: float) -> void:
	for who: AnimatedSprite2D in _flips.keys():
		var b: float = (vis - _flips[who]) / Conductor.seconds_per_beat   # beats since beat 1
		if who == tongs:
			# Your presses reach the game input_offset after the beat you heard, so
			# your own tongs run that much behind the music up to the toss (beat 2)
			# -- an on-time press then lands exactly as the grab does, with no stall
			# and jump -- and catch up by the landing on beat 3, which is on the music.
			var lag := Conductor.input_offset / Conductor.seconds_per_beat
			b -= lag * clampf(2.0 - b, 0.0, 1.0)
			# your flip waits just short of each beat until that beat's press lands
			if not _pflip.is_empty() and _pflip["hit"] < 3:
				b = minf(b, float(_pflip["hit"]) - 0.15)
		var f: float
		if b < 0.0:
			f = lerpf(0.0, FLIP_GRAB, clampf((b + FLIP_REACH) / FLIP_REACH, 0.0, 1.0))
		elif b < 1.0:
			f = lerpf(FLIP_GRAB, FLIP_TOP, b)
		elif b < 2.0:
			f = lerpf(FLIP_TOP, FLIP_LAND, b - 1.0)
		elif b < 2.0 + FLIP_RETURN:
			f = lerpf(FLIP_LAND, FLIP_END, (b - 2.0) / FLIP_RETURN)
		else:
			_flips.erase(who)
			f = 0.0
		if who.animation != &"flip":
			who.animation = &"flip"
		who.stop()
		who.frame = int(f)


## Sounds for one press of a move. A flip / pop: the grab on the press, a whoosh
## on the let-go, and a soft sizzle when it lands.
func _sound(cue: String, part: int) -> void:
	if cue == "tap":
		_play_sfx("tong", 0.0)
		return
	match clampi(part, 0, 2):
		0:
			_play_sfx("flip", -2.0)
		1:
			_play_sfx("whoosh", -3.0)
		2:
			# lands with a sharp sear (sizzle.wav swells in over ~0.5 s, so on its
			# own it's heard well after the beat -- it's only the quiet tail now)
			_play_sfx("land", -4.0)
			if cue == "pop":
				_play_sfx("pop", 0.0)
			else:
				_play_sfx("sizzle", -20.0)


func _play_sfx(key: String, db: float) -> void:
	if not _sfx.has(key):
		return
	var p := _next_free()
	p.stream = _sfx[key]
	p.volume_db = db
	p.play()


func _next_free() -> AudioStreamPlayer:
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	return p


## A short whoosh: noise swept from bright to dark.
func _synth_whoosh() -> AudioStreamWAV:
	var rate := 44100
	var n := int(0.3 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in n:
		var k := float(i) / n
		var env := clampf(k / 0.015, 0.0, 1.0) * pow(1.0 - k, 2.0)   # ~4 ms attack: heard on the let-go, not after it
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * lerpf(0.6, 0.06, k)
		lp2 += (lp - lp2) * 0.02
		out[i] = env * (lp - lp2) * 1.6
	return _to_wav(out, rate)


## The patty slapping onto the hot grill: a hissy burst that hits at once and
## dies away over ~0.3 s.
func _synth_sear() -> AudioStreamWAV:
	var rate := 44100
	var n := int(0.32 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var lp := 0.0
	var thump := 0.0
	for i in n:
		var t := float(i) / rate
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.35
		var hiss := (x - lp) * exp(-t * 11.0) * clampf(t / 0.002, 0.0, 1.0)
		thump = sin(TAU * 110.0 * t) * exp(-t * 40.0)   # the meat hitting the bars
		out[i] = hiss + 0.6 * thump
	return _to_wav(out, rate)


## A little service bell: each pitch with an inharmonic overtone, struck and ringing out.
func _synth_ding(freqs: Array, dur: float) -> AudioStreamWAV:
	var rate := 44100
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		for f: float in freqs:
			v += sin(TAU * f * t) * exp(-t * 7.0) + 0.35 * sin(TAU * f * 2.76 * t) * exp(-t * 16.0)
		out[i] = v * clampf(t / 0.002, 0.0, 1.0)
	return _to_wav(out, rate)


## A shaker rattle: a few quick bursts of hissy noise. `bright` 0..1 (salt is
## brighter than pepper), `grains` = how many bursts.
func _synth_shake(bright: float, grains: int) -> AudioStreamWAV:
	var rate := 44100
	var n := int(0.12 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5 + grains
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var env := 0.0
		for g in grains:   # bursts 22 ms apart, each dying fast
			var tg := t - g * 0.022
			if tg >= 0.0:
				env += exp(-tg * 90.0) * (1.0 - 0.15 * g)
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * lerpf(0.15, 0.6, bright)
		out[i] = (x - lp) * env      # high-passed noise
	return _to_wav(out, rate)


func _to_wav(data: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var pk := 0.0001
	for v in data:
		pk = maxf(pk, absf(v))
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i] / pk * 0.9, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = bytes
	return w


# --- drawing -----------------------------------------------------------------------

func _draw_fx() -> void:
	var now := Conductor.song_position
	var font := ThemeDB.fallback_font
	var l := _fx_layer
	# your plate (the patty lands on it with the pop) and the salt + pepper shakers
	_draw_plate(l)
	for season in SEASONS:
		_draw_shaker(l, season)
	if _flip_due != "" and _fumble.is_empty() and not _flips.has(tongs):
		_draw_flip_due(l, font)
	for f in _fx:
		var t: float = maxf(now - f["t0"], 0.0)
		var pos: Vector2 = f["pos"]
		match f["kind"]:
			"steam":   # three puffs drifting up off the patty
				for i in 3:
					var p := pos + Vector2((i - 1) * 26.0 + sin(t * 6.0 + i) * 6.0, -30.0 - t * 90.0 - i * 10.0)
					l.draw_circle(p, 10.0 + t * 14.0, Color(0.85, 0.85, 0.85, clampf(0.7 - t * 0.9, 0.0, 1.0)))
			"clack":   # comic impact lines bursting out where the tong tips snap shut
				var k := clampf(t / 0.22, 0.0, 1.0)
				if k < 1.0:
					var col: Color = f["col"]
					var e := 1.0 - pow(1.0 - k, 3.0)          # fast out, then settles
					for i in 8:
						var a := TAU * i / 8.0 + 0.2
						var d := Vector2(cos(a), sin(a))
						var ln := 22.0 if i % 2 == 0 else 14.0
						var r0 := 16.0 + e * 22.0
						l.draw_line(pos + d * r0, pos + d * (r0 + ln * (1.0 - k * 0.7)), Color(col, 1.0 - k), 5.0 * (1.0 - k * 0.5))
					if k < 0.35:
						l.draw_circle(pos, 14.0 * (1.0 - k / 0.35), Color(1, 1, 0.85, 0.9))
			"pop":     # burst where the patty lands
				for i in 8:
					var a := TAU * i / 8.0
					l.draw_circle(pos + Vector2(cos(a), sin(a)) * (20.0 + t * 160.0) + Vector2(0, -30),
						6.0 * (1.0 - clampf(t, 0.0, 1.0)), Color(1, 0.85, 0.3, clampf(1.0 - t, 0.0, 1.0)))
			"miss":    # brief smoky puff: burnt
				l.draw_circle(pos + Vector2(0, -20 - t * 40.0), 18.0 + t * 30.0, Color(0.3, 0.3, 0.3, clampf(0.6 - t, 0.0, 1.0)))
			"x":       # big red X over your tongs: that wasn't right
				var a := clampf(1.0 - t / 0.7, 0.0, 1.0)
				_draw_x(l, pos + Vector2(0, 100 - t * 20.0), 30.0 + t * 10.0, Color(0.85, 0.15, 0.1, a), 10.0)
			"judge":   # PERFECT! / GOOD / MISS pops up over your tongs, overshoots, floats off
				var a := clampf((0.75 - t) / 0.25, 0.0, 1.0)
				var s := 1.0 + 0.5 * exp(-t * 18.0) * cos(t * 30.0)
				var col: Color = f["col"]
				l.draw_set_transform(pos + Vector2(0, -t * 40.0), 0.0, Vector2(s, s))
				l.draw_string_outline(font, Vector2(-150, 0), f["text"], HORIZONTAL_ALIGNMENT_CENTER, 300, 34, 9, Color(0.15, 0.1, 0.08, a))
				l.draw_string(font, Vector2(-150, 0), f["text"], HORIZONTAL_ALIGNMENT_CENTER, 300, 34, Color(col, a))
				l.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"pinch":   # a pinch of salt / pepper arcs from the shaker onto the patty
				var rng := RandomNumberGenerator.new()
				rng.seed = f["seed"]
				var to: Vector2 = f["to"]
				for i in 12:
					var k := clampf((t - rng.randf() * 0.06) / FLY, 0.0, 1.0)
					var spread := Vector2(rng.randf_range(-40, 40), rng.randf_range(-8, 8))
					if k > 0.0 and k < 1.0:
						var p := pos.lerp(to + spread, k) + Vector2(0, -150.0 * sin(PI * k))
						_grain(l, p, f["season"], 1.0)
					elif k >= 1.0 and t < FLY + 0.35:   # settles on the patty, then fades
						_grain(l, to + spread, f["season"], 1.0 - (t - FLY) / 0.35)
			"spill":   # missed: the pinch pours out onto the floor
				var rng := RandomNumberGenerator.new()
				rng.seed = f["seed"]
				for i in 12:
					var v := Vector2(rng.randf_range(-60, 60), rng.randf_range(-140, -40))
					var p := pos + Vector2(0, -50) + v * t + Vector2(0, 1200) * t * t
					if p.y < VP.y + 10.0:
						_grain(l, p, f["season"], 1.0)
			"cue_ring":   # a cue: a ring swells out around what needs you
				var k := clampf(t / 0.45, 0.0, 1.0)
				if k < 1.0:
					var col: Color = f["col"]
					l.draw_arc(pos, 34.0 + 46.0 * (1.0 - pow(1.0 - k, 3.0)), 0.0, TAU, 40, Color(INK, 0.5 * (1.0 - k)), 9.0)
					l.draw_arc(pos, 34.0 + 46.0 * (1.0 - pow(1.0 - k, 3.0)), 0.0, TAU, 40, Color(col, 1.0 - k), 5.0)
			"bubbles":    # the patty's ready: grease bubbles swell up off it and pop
				var rng := RandomNumberGenerator.new()
				rng.seed = f["seed"]
				var col: Color = f["col"]
				for i in 7:
					var d := rng.randf() * 0.12
					var k := clampf((t - d) / 0.5, 0.0, 1.0)
					if k > 0.0 and k < 1.0:
						var p := pos + Vector2(rng.randf_range(-55, 55), -8.0 - k * rng.randf_range(30, 70))
						var r := rng.randf_range(5, 10) * (0.5 + k)
						l.draw_arc(p, r, 0.0, TAU, 16, Color(col.lightened(0.4), 1.0 - k), 3.0)
			"sparks":  # grease sparks spitting off the grill
				var rng := RandomNumberGenerator.new()
				rng.seed = f["seed"]
				for i in int(f["n"]):
					var v := Vector2(rng.randf_range(-260, 260), rng.randf_range(-420, -200))
					var p := pos + Vector2(rng.randf_range(-60, 60), 0) + v * t + Vector2(0, 900) * t * t
					var a := clampf(1.0 - t / 0.5, 0.0, 1.0)
					if a > 0.0:
						l.draw_line(p, p - v.normalized() * 10.0, Color(1, 0.6 + rng.randf() * 0.3, 0.15, a), 4.0)

	if _closeup_ms >= 0 and Time.get_ticks_msec() >= _closeup_ms:
		_draw_closeup(l, font)
		return
	if _phase == Phase.SONG:
		l.draw_string(font, Vector2(VP.x - 250, 52), "SCORE  %d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, INK)
		var pulse := 1.0 + 0.35 * clampf(1.0 - (Time.get_ticks_msec() - _combo_ms) / 180.0, 0.0, 1.0)
		var ccol := INK.lerp(PERFECT_COL.darkened(0.2), clampf(combo / 10.0, 0.0, 1.0))
		l.draw_set_transform(Vector2(VP.x - 250, 80), 0.0, Vector2(pulse, pulse))
		l.draw_string(font, Vector2(0, 8), "COMBO  x%d" % combo, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ccol)
		l.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		l.draw_string(font, Vector2(VP.x - 250, 122), "BURGER  %d / %d" % [mini(_served.size() + 1, _burger_count), _burger_count],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(INK, 0.75))
	else:
		_draw_practice(l, font)
	if _held and _pflip.get("hit", 0) == 1 and not _pflip.get("fail", true):
		_draw_hold_ring(l, font)
	if banner != "":
		l.draw_string_outline(font, Vector2(0, VP.y * 0.42), banner, HORIZONTAL_ALIGNMENT_CENTER, VP.x, 56, 8, Color(0.15, 0.1, 0.08))
		l.draw_string(font, Vector2(0, VP.y * 0.42), banner, HORIZONTAL_ALIGNMENT_CENTER, VP.x, 56, Color.WHITE)
	if _finished:
		_draw_results(l, font, Vector2(VP.x / 2 - 200, VP.y / 2 - 185))


## Behind the grill and tongs: the picnic table, with the burgers you've served on it.
func _draw_back() -> void:
	var l := _back_layer
	var tex := _tex("picnic_table")
	if tex:
		var k := minf(table_rect.size.x / tex.get_width(), table_rect.size.y / tex.get_height())
		var sz := Vector2(tex.get_width(), tex.get_height()) * k
		l.draw_texture_rect(tex, Rect2(table_rect.get_center() - sz * 0.5, sz), false)
	else:
		_placeholder(l, table_rect, "picnic_table", 1.0, 1.0)
	var now := Conductor.song_position
	for i in mini(_served.size(), table_slots.size()):
		var r: Dictionary = _served[i]
		if now - r["t"] >= SERVE_GO + SERVE_FLY:
			_draw_burger(l, table_slots[i], served_scale, r["landed"], r["raw"], 0.0, true, 10.0, false)


## Your plate. Right after a pop it holds the finished burger: the top bun drops
## on, then it hops off onto the picnic table, and a fresh bottom bun waits for
## the next patty.
func _draw_plate(l: Node2D) -> void:
	var recs: Array = _served
	var base := bun_pos + Vector2(0, 60)
	var r: Dictionary = recs.back() if not recs.is_empty() else {}
	var age: float = Conductor.song_position - r.get("t", -100.0)
	if r.is_empty() or age < 0.0 or age >= SERVE_GO:
		_draw_burger(l, base, PLAY_S, false, 1.0, 0.0, false)
	else:
		_draw_burger(l, base, PLAY_S, r["landed"], r["raw"], 0.0, age >= SERVE_HOLD, age - SERVE_HOLD)
	if r.is_empty() or age < SERVE_GO or age >= SERVE_GO + SERVE_FLY:
		return
	var i := recs.size() - 1
	if i >= table_slots.size():
		return
	var to := table_slots[i]
	var s_to := served_scale
	var k := (age - SERVE_GO) / SERVE_FLY
	var e := k * k * (3.0 - 2.0 * k)
	var p := base.lerp(to, e) + Vector2(0, -160.0 * sin(PI * k))
	_draw_burger(l, p, lerpf(PLAY_S, s_to, e), r["landed"], r["raw"], 0.0, true, 10.0, false)


## The patty's waiting to be flipped: a bobbing "!" over it (gold for the pop,
## which goes on the bun), until you grab it.
func _draw_flip_due(l: Node2D, font: Font) -> void:
	var col := POP_COL if _flip_due == "pop" else CUE_COL
	var bob := sin(Time.get_ticks_msec() / 90.0) * 4.0 - 30.0 * _hop_amount("patty")
	var c := patty_pos + Vector2(0, -78 + bob)
	l.draw_circle(c, 24.0, INK)
	l.draw_circle(c, 20.0, col)
	l.draw_string(font, c + Vector2(-20, 11), "!", HORIZONTAL_ALIGNMENT_CENTER, 40, 32, INK)
	if _flip_due == "pop":
		l.draw_string_outline(font, c + Vector2(-80, -34), "ON THE BUN!", HORIZONTAL_ALIGNMENT_CENTER, 160, 18, 6, INK)
		l.draw_string(font, c + Vector2(-80, -34), "ON THE BUN!", HORIZONTAL_ALIGNMENT_CENTER, 160, 18, col)


## While you hold a patty up: a ring over your tongs filling toward beat 2 -- let go when it's full.
func _draw_hold_ring(l: Node2D, font: Font) -> void:
	var beat1: float = _flips.get(tongs, Conductor.visual_position)
	var k := clampf((Conductor.visual_position - beat1) / Conductor.seconds_per_beat, 0.0, 1.0)
	var c := you_pos + Vector2(0, -70)
	l.draw_circle(c, 30.0, Color(1, 0.97, 0.88, 0.9))
	l.draw_arc(c, 30.0, -PI / 2, -PI / 2 + TAU * k, 40, PERFECT_COL if k > 0.85 else Color(0.95, 0.55, 0.2), 8.0)
	l.draw_arc(c, 34.0, 0.0, TAU, 40, INK, 3.0)
	l.draw_string(font, c + Vector2(-60, 8), "HOLD", HORIZONTAL_ALIGNMENT_CENTER, 120, 18, INK)


## Where a cue happens: over the shakers (seasoning) or the patty (flip).
func _cue_spot(cue: String) -> Vector2:
	if cue == "tap":
		return (salt_pos + pepper_pos) * 0.5 + Vector2(0, -50)
	return patty_pos + Vector2(0, -60)


func _draw_practice(l: Node2D, font: Font) -> void:
	if _phase == Phase.CARD:
		_draw_card(l, font)
		return
	var cyc: Variant = _current_cycle()
	var b := Conductor.visual_position / Conductor.seconds_per_beat
	var cue_col := Color(1.0, 0.6, 0.2)
	var you_col := Color(1, 0.88, 0.3)
	var strip := Rect2(VP.x * 0.5 - 230, 10, 460, 128)
	var cue: String = ["tap", "flip"][_step]
	if cyc == null:
		_draw_strip(l, font, strip, cue, [], fposmod(b, 4.0), [], "Get ready...", INK, INK)
	elif b < cyc["start"] + 4.0:
		_label(l, font, _cue_spot(cue), "LISTEN", cue_col)
		_draw_strip(l, font, strip, cue, cyc["cues"], b - cyc["start"], [],
			"The cue -- watch & listen", Color(0.75, 0.4, 0.1), cue_col)
	else:
		_label(l, font, you_pos, "YOUR TURN!", you_col)
		_draw_strip(l, font, strip, cue, cyc["you"], b - cyc["start"] - 4.0, cyc["strays"],
			"Your turn -- same rhythm with SPACE!", Color(0.7, 0.45, 0.0), Color(0.36, 0.62, 0.32), cyc["taps"])

	if not _toast.is_empty():
		var age := (Time.get_ticks_msec() - int(_toast["ms"])) / 1000.0
		if age < 1.8:
			var a := clampf((1.8 - age) / 0.4, 0.0, 1.0)
			var col: Color = _toast["col"]
			var at := Vector2(0, strip.end.y + 34)
			l.draw_string_outline(font, at, _toast["text"], HORIZONTAL_ALIGNMENT_CENTER, VP.x, 26, 8, Color(1, 1, 1, a))
			l.draw_string(font, at, _toast["text"], HORIZONTAL_ALIGNMENT_CENTER, VP.x, 26, Color(col, a))

	var box := Rect2(VP.x - 330, VP.y - 132, 310, 112)   # bottom-right: clear of the grill and both tongs
	var x := box.position.x
	var y := box.position.y
	var w := box.size.x
	l.draw_style_box(_panel_sb, box)
	var step_text := "Practice 1/2: Seasoning" if _step == 0 else "Practice 2/2: The flip"
	l.draw_string(font, Vector2(x, y + 34), step_text, HORIZONTAL_ALIGNMENT_CENTER, w, 22, INK)
	var gap := 40.0
	var cx := x + w * 0.5 - gap * (practice_goal - 1) * 0.5
	for i in practice_goal:
		var c := Vector2(cx + gap * i, y + 62)
		if i < _step_ok:
			l.draw_circle(c, 13.0, Color(0.36, 0.62, 0.32))
		else:
			l.draw_arc(c, 13.0, 0.0, TAU, 32, Color(INK, 0.45), 3.0)
	l.draw_string(font, Vector2(x, y + 98), "S to skip the practice", HORIZONTAL_ALIGNMENT_CENTER, w, 16, Color(INK, 0.6))


## One bar as a timeline: beats 1-4 with "&"s, a circle for each press of
## `cue`, filled as `marks` says (0 empty, 1 hit, 2 missed), red ticks for extra
## presses, a small marker where each counted press landed, and a playhead at `head` beats into the bar (< 0 or > 4: none).
func _draw_strip(l: Node2D, font: Font, r: Rect2, cue: String, marks: Array, head: float,
		strays: Array, title: String, title_col: Color, fill: Color, taps: Array = []) -> void:
	l.draw_style_box(_panel_sb, r)
	l.draw_string(font, Vector2(r.position.x, r.position.y + 32), title, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 24, title_col)
	var x0 := r.position.x + 50
	var sp := (r.size.x - 100) / 3.5
	var ly := r.position.y + 76
	var bx := func(beat: float) -> float: return x0 + beat * sp
	l.draw_line(Vector2(x0 - 20, ly), Vector2(bx.call(3.5) + 20, ly), Color(INK, 0.35), 3.0)
	for i in 4:
		l.draw_string(font, Vector2(bx.call(i) - 30, ly - 18), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 60, 22, Color(INK, 0.8))
		l.draw_line(Vector2(bx.call(i), ly - 8), Vector2(bx.call(i), ly + 8), Color(INK, 0.5), 3.0)
		l.draw_string(font, Vector2(bx.call(i + 0.5) - 30, ly - 18), "&", HORIZONTAL_ALIGNMENT_CENTER, 60, 16, Color(INK, 0.4))
	var pat: Array = PATTERN[cue]
	var words: Array = ["salt", "pepper"] if cue == "tap" else ["HOLD", "LET GO", "sizzle"]
	if cue != "tap":   # the hold: a fat bar from the press to the release, filling as it goes
		var x0b: float = bx.call(pat[0])
		var x1b: float = bx.call(pat[1])
		l.draw_line(Vector2(x0b, ly), Vector2(x1b, ly), Color(INK, 0.2), 14.0)
		var held: float = clampf(head - pat[0], 0.0, pat[1] - pat[0]) if marks.size() > 0 and marks[0] == 1 else 0.0
		if held > 0.0:
			l.draw_line(Vector2(x0b, ly), Vector2(bx.call(pat[0] + held), ly), fill, 14.0)
	for i in pat.size():
		var c := Vector2(bx.call(pat[i]), ly)
		var m: int = marks[i] if i < marks.size() else 0
		var rad := 9.0 if cue != "tap" and i == 2 else 14.0   # the landing plays itself: smaller
		if m == 1:
			l.draw_circle(c, rad, fill)
		elif m == 2:
			l.draw_circle(c, rad, Color(1, 0.97, 0.88))
			_draw_x(l, c, rad * 0.8, Color(0.85, 0.2, 0.15), 5.0)
		else:
			l.draw_circle(c, rad, Color(1, 0.97, 0.88))
		l.draw_arc(c, rad, 0.0, TAU, 32, INK, 3.0)
		l.draw_string(font, Vector2(c.x - 40, ly + 38), words[i], HORIZONTAL_ALIGNMENT_CENTER, 80, 16, Color(INK, 0.75))
	for s in strays:
		_draw_x(l, Vector2(bx.call(s), ly), 9.0, Color(0.85, 0.2, 0.15), 4.0)
	for tp in taps:      # where each counted press actually landed (on the circle = perfect)
		var tx: float = bx.call(tp)
		l.draw_line(Vector2(tx, ly - 19), Vector2(tx, ly + 19), INK, 4.0)
	if head >= -0.25 and head < 3.75:
		var hx: float = bx.call(clampf(head, 0.0, 3.75))
		l.draw_line(Vector2(hx, ly - 26), Vector2(hx, ly + 22), Color(0.85, 0.3, 0.2, 0.8), 4.0)


func _draw_x(l: Node2D, c: Vector2, s: float, col: Color, w: float) -> void:
	l.draw_line(c + Vector2(-s, -s), c + Vector2(s, s), col, w)
	l.draw_line(c + Vector2(-s, s), c + Vector2(s, -s), col, w)


## The tutorial's explainer cards.
func _draw_card(l: Node2D, font: Font) -> void:
	l.draw_rect(Rect2(Vector2.ZERO, VP), Color(0, 0, 0, 0.35))
	var cue_col := Color(1.0, 0.6, 0.2)
	var you_col := Color(1, 0.88, 0.3)
	var box := Rect2(140, 286, VP.x - 280, 350)
	var x := box.position.x
	var w := box.size.x
	var y := box.position.y
	var lines: Array = []          # [text, size, color]
	var strip_cue := ""
	match _card:
		Card.WELCOME:
			_label(l, font, you_pos, "YOU", you_col)
			_label(l, font, patty_pos + Vector2(0, -60), "THE GRILL", cue_col)
			lines = [["HOW TO PLAY", 34, INK],
				["The tongs are YOURS.", 24, Color(0.6, 0.4, 0.0)],
				["The grill tells you what it needs, one bar ahead:", 22, INK],
				["shakers hop = season it.  Patty dings = flip it!", 22, Color(0.75, 0.4, 0.1)],
				["", 10, INK],
				["Listen to the cue's rhythm, then press SPACE", 22, INK],
				["in that same rhythm on the next bar.", 22, INK]]
		Card.CLACK:
			lines = [["MOVE 1:  SEASON IT", 34, INK],
				["Salt and pepper hop on \"3-and-4\"? Next bar, shake them", 22, INK],
				["in that rhythm: SALT, then PEPPER. Miss = on the floor!", 22, INK]]
			strip_cue = "tap"
		Card.FLIP:
			lines = [["MOVE 2:  THE FLIP", 34, INK],
				["Patty dings on 1 and 2? It's ready! Next bar,", 22, INK],
				["HOLD SPACE on 1 to grab it, LET GO on 2 to toss it.", 22, INK]]
			strip_cue = "flip"
		Card.READY:
			lines = [["YOU'VE GOT IT!", 34, Color(0.25, 0.55, 0.25)],
				["Now the real song -- cook THREE burgers!", 22, INK],
				["Listen for the cue, answer it on the next bar.", 22, INK],
				["", 10, INK],
				["Shakers hop?  Salt, then pepper.", 22, INK],
				["Patty dings?  HOLD on 1, let go on 2.", 22, INK],
				["Gold ding = it goes on the bun -- next burger!", 22, Color(0.75, 0.25, 0.2)]]
	l.draw_style_box(_panel_sb, box)
	var ty := y + 50.0
	for ln in lines:
		l.draw_string(font, Vector2(x, ty), ln[0], HORIZONTAL_ALIGNMENT_CENTER, w, ln[1], ln[2])
		ty += ln[1] + 12.0
	if strip_cue != "":
		# animate a playhead across a sample bar, the circles filling as it passes
		var t := fposmod(Time.get_ticks_msec() / 1000.0 / Conductor.seconds_per_beat, 6.0) - 1.0
		var marks: Array = []
		for p in PATTERN[strip_cue]:
			marks.append(1 if t >= p else 0)
		_draw_strip(l, font, Rect2(x + w * 0.5 - 230, ty - 6, 460, 128), strip_cue, marks, t, [],
			"Where the presses go:", INK, Color(0.36, 0.62, 0.32))
	var blink := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 250.0)
	l.draw_string(font, Vector2(x, box.end.y - 18), "Press SPACE to continue", HORIZONTAL_ALIGNMENT_CENTER, w, 20, Color(INK, blink))


## Outlined label with a down arrow whose tip is at `tip`.
func _label(l: Node2D, font: Font, tip: Vector2, text: String, col: Color) -> void:
	var at := Vector2(tip.x - 170, tip.y - 40)
	l.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 340, 40, 8, Color(0.15, 0.1, 0.08, col.a))
	l.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, 340, 40, col)
	l.draw_colored_polygon(PackedVector2Array([tip + Vector2(-13, -30), tip + Vector2(13, -30), tip]), col)


## The ending: zoom into your bun, then a close-up of all your burgers in a row --
## each as cooked and seasoned as you made it -- with the results beside them.
func _draw_closeup(l: Node2D, font: Font) -> void:
	var age := (Time.get_ticks_msec() - _closeup_ms) / 1000.0
	if age < CLOSEUP_IRIS:   # zoom: a white disc swells out of your bun to fill the screen
		var k := age / CLOSEUP_IRIS
		l.draw_circle(bun_pos, 1400.0 * k * k, Color(1, 0.98, 0.93))
		return
	var t := age - CLOSEUP_IRIS
	var show_results := _finished and t >= RESULTS_AFTER
	l.draw_rect(Rect2(Vector2.ZERO, VP), Color(0.99, 0.94, 0.84))
	_draw_art(l, "table", Vector2.ZERO, 1.0)
	# the row shrinks and slides left to make room for the results
	var slide := clampf((t - RESULTS_AFTER) / 0.4, 0.0, 1.0) if show_results else 0.0
	slide = slide * slide * (3.0 - 2.0 * slide)
	var cx := lerpf(VP.x * 0.5, 330.0, slide)
	var bs := lerpf(0.55, 0.34, slide)
	var spread := lerpf(350.0, 212.0, slide)
	var n := _served.size()
	for i in n:
		var r: Dictionary = _served[i]
		var base := Vector2(cx + (i - (n - 1) * 0.5) * spread, 592.0)
		var bt := t - i * 0.2          # top buns drop on one after another
		_draw_burger(l, base, bs, r["landed"], r["raw"], r["season"], bt >= 0.0, bt)
		if bt > 0.4 and r["landed"]:   # steam curling up off it
			var top := base + (Vector2(0, ART["bun_top"][1].position.y) - Vector2(0, BURGER.y)) * bs
			for j in 3:
				var pts := PackedVector2Array()
				var ph := t * 2.0 + j * 1.7 + i
				for m in 8:
					var y := -m * 12.0 - fposmod(ph, 1.0) * 22.0
					pts.append(top + Vector2((j - 1) * 90.0 * bs + sin(m * 0.6 + ph * 3.0) * 10.0, y))
				l.draw_polyline(pts, Color(1, 1, 1, 0.75), 6.0)
				l.draw_polyline(pts, Color(0.75, 0.75, 0.78, 0.35), 2.0)
		if t > 0.6:   # how this one came out
			var txt := _doneness(r["raw"]) if r["landed"] else "No patty"
			if r["landed"] and r["season"] < 0.5:
				txt += ", bland"
			l.draw_string_outline(font, Vector2(base.x - 110, 628), txt, HORIZONTAL_ALIGNMENT_CENTER, 220, 20, 6, Color(1, 0.98, 0.93))
			l.draw_string(font, Vector2(base.x - 110, 628), txt, HORIZONTAL_ALIGNMENT_CENTER, 220, 20, INK)
	# a white flash fading out over the cut
	l.draw_rect(Rect2(Vector2.ZERO, VP), Color(1, 0.98, 0.93, clampf(1.0 - t / 0.25, 0.0, 1.0)))
	# caption
	var cap := _verdict()
	var ck := clampf((t - 0.5) / 0.15, 0.0, 1.0)
	if ck > 0.0:
		var s := 1.0 + 0.4 * (1.0 - ck)
		var any := _served.any(func(r): return r["landed"])
		l.draw_set_transform(Vector2(cx, 92), -0.04, Vector2(s, s))
		l.draw_string_outline(font, Vector2(-300, 0), cap, HORIZONTAL_ALIGNMENT_CENTER, 600, 54, 12, Color(0.15, 0.1, 0.08, ck))
		l.draw_string(font, Vector2(-300, 0), cap, HORIZONTAL_ALIGNMENT_CENTER, 600, 54, Color(PERFECT_COL if any else Color.WHITE, ck))
		l.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if show_results:
		var rk := clampf((t - RESULTS_AFTER - 0.2) / 0.3, 0.0, 1.0)
		_draw_results(l, font, Vector2(lerpf(VP.x + 20, VP.x - 450, rk * (2.0 - rk)), VP.y / 2 - 185))


## A burger is perfect when every flip and every clack for it landed.
func _perfect(r: Dictionary) -> bool:
	return r["landed"] and r["raw"] < 0.15 and r["season"] >= 0.999


## The close-up's caption: how good are the burgers you made?
func _verdict() -> String:
	var landed := 0
	var perfect := 0
	var raw := false
	var bland := false
	for r in _served:
		if not r["landed"]:
			continue
		landed += 1
		perfect += 1 if _perfect(r) else 0
		raw = raw or r["raw"] >= 0.55
		bland = bland or r["season"] < 0.5
	if landed == 0:
		return "No burgers..."
	if perfect == _served.size():
		return "PERFECT BURGER!" if perfect == 1 else "%d PERFECT BURGERS!" % perfect
	if landed < _served.size():
		return "Lost a patty..."
	if raw:
		return "Still a bit raw..."
	if bland:
		return "Kinda bland..."
	return "ORDER UP!"


func _doneness(raw: float) -> String:
	if raw < 0.15: return "Well done"
	if raw < 0.4: return "Medium"
	if raw < 0.65: return "Medium rare"
	return "Raw!"


## One of your drawings, or null if that file isn't there yet.
func _tex(art_name: String) -> Texture2D:
	if not _art.has(art_name):
		var path: String = ART_DIR + ART[art_name][0]
		_art[art_name] = load(path) if ResourceLoader.exists(path) else null
	return _art[art_name]


## Draw art `art_name` with its local origin at `at`, scaled by `s` and turned by
## `rot`. Burger layers cover the whole BURGER canvas; the rest fit in their box.
## No file yet: a labelled placeholder box.
func _draw_art(l: Node2D, art_name: String, at: Vector2, s: float, rot := 0.0, alpha := 1.0, sy := 1.0) -> void:
	var box: Rect2 = ART[art_name][1]
	var tex := _tex(art_name)
	l.draw_set_transform(at, rot, Vector2(s, s * sy))
	if tex:
		var r := Rect2(Vector2.ZERO, BURGER)
		if not (ART[art_name][0] as String).begins_with("burger/"):
			var k := minf(box.size.x / tex.get_width(), box.size.y / tex.get_height())
			var sz := Vector2(tex.get_width(), tex.get_height()) * k
			r = Rect2(box.get_center() - sz * 0.5, sz)
		l.draw_texture_rect(tex, r, false, Color(1, 1, 1, alpha))
	else:
		_placeholder(l, box, art_name, alpha, s)
	l.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A dashed box with the art's name in it, standing in for a drawing.
func _placeholder(l: Node2D, box: Rect2, label: String, alpha: float, s: float, fill := Color(1, 1, 1, 0.55)) -> void:
	var ink := Color(INK, 0.6 * alpha)
	var w := 3.0 / s
	l.draw_rect(box, Color(fill, fill.a * alpha))
	var c := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
	for i in 4:
		l.draw_dashed_line(c[i], c[(i + 1) % 4], ink, w, 10.0 / s)
	var fs := clampi(int(minf(box.size.y * 0.5, 16.0 / s)), 6, 200)
	l.draw_string(ThemeDB.fallback_font, Vector2(box.position.x, box.get_center().y + fs * 0.35), label,
		HORIZONTAL_ALIGNMENT_CENTER, box.size.x, fs, ink)


## The burger art piled up, its BURGER canvas bottom-middle at `base`, scale `s`:
## plate, bottom bun, the patty if it's on (raw fading into cooked), seasoning,
## and the top bun dropping on (`t` = seconds since it started to fall).
func _draw_burger(l: Node2D, base: Vector2, s: float, patty: bool, raw: float, seasoning: float, top_bun: bool, t := 0.0, plate := true) -> void:
	var o := base - Vector2(BURGER.x * 0.5, BURGER.y) * s
	if plate:
		_draw_art(l, "plate", o, s)
	_draw_art(l, "bun_bottom", o, s)
	if patty:
		if _tex("patty_raw") == null and _tex("patty_cooked") == null:
			# one placeholder, pink to brown with the cooking
			var meat := Color(0.38, 0.2, 0.12).lerp(Color(0.93, 0.45, 0.47), raw)
			l.draw_set_transform(o, 0.0, Vector2(s, s))
			_placeholder(l, ART["patty_raw"][1], "patty_raw / patty_cooked", 1.0, s, Color(meat, 0.85))
			l.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			_draw_art(l, "patty_cooked", o, s)
			if raw > 0.01:
				_draw_art(l, "patty_raw", o, s, 0.0, raw)
		if seasoning > 0.0 and _tex("seasoning"):
			_draw_art(l, "seasoning", o, s, 0.0, seasoning)
		elif seasoning > 0.0:   # no drawing yet: salt + pepper grains, as many as you landed
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			var box: Rect2 = ART["seasoning"][1]
			for i in int(40 * seasoning):
				var p := box.position + Vector2(rng.randf() * box.size.x, rng.randf() * box.size.y)
				_grain(l, o + p * s, SEASONS[i % 2], 1.0)
	if not top_bun:
		return
	# top bun drops in and squashes
	var drop := 0.0
	var sq := 1.0
	if t < 0.25:
		var k := t / 0.25
		drop = -580.0 * s * (1.0 - k * k)   # from higher up the bigger the burger
	elif t < 0.6:
		var k := (t - 0.25) / 0.35
		sq = 1.0 - 0.22 * sin(k * PI) * (1.0 - k)
	var pivot := o + BUN_TOP_PIVOT * s + Vector2(0, drop)
	var sx := s / sq
	_draw_art(l, "bun_top", pivot - Vector2(BUN_TOP_PIVOT.x * sx, BUN_TOP_PIVOT.y * s * sq), sx, 0.0, 1.0, sq * sq)


## Where a shaker stands (its middle).
func _shaker_at(season: String) -> Vector2:
	return salt_pos if season == "salt" else pepper_pos


## A salt / pepper shaker standing on the table. Seasoning: it lifts and leans
## out toward the grill, shakes, and sets back down. Wobbles on a miss.
func _draw_shaker(l: Node2D, season: String) -> void:
	var p := _shaker_at(season)
	# its shadow on the table top, so it stands there instead of floating
	var foot := p + Vector2(0, 23)
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(foot + Vector2(cos(a) * 20.0, sin(a) * 5.0))
	var rot := 0.0
	var lift := 0.0
	var j: Array = _jolt.get(season, [-100000, true])
	var ms := float(Time.get_ticks_msec() - int(j[0]))
	if j[1] and ms < SEASON_MS:
		# up and out toward the grill fast, a few shakes, then back down onto the table
		var k := ms / SEASON_MS
		lift = smoothstep(0.0, 0.18, k) * (1.0 - smoothstep(0.65, 1.0, k))
		p += SEASON_REACH * lift
		rot = 1.15 * lift + 0.2 * sin(k * TAU * 5.0) * lift
	elif not j[1] and ms < 260.0:
		rot = 0.3 * sin(ms / 260.0 * TAU * 2.5) * (1.0 - ms / 260.0)
	l.draw_colored_polygon(pts, Color(0.35, 0.22, 0.05, 0.35 * (1.0 - 0.6 * lift)))
	var hop := _hop_amount(season)   # a seasoning cue: it jumps and rattles
	p += Vector2(0, -16.0 * hop)
	rot += 0.25 * sin(Time.get_ticks_msec() / 22.0) * hop
	_draw_art(l, season, p, 1.0 + 0.12 * hop, rot)


## One grain of salt (white) or pepper (black).
func _grain(l: Node2D, p: Vector2, season: String, alpha: float) -> void:
	alpha = clampf(alpha, 0.0, 1.0)
	if season == "salt":
		l.draw_circle(p, 3.5, Color(INK, 0.7 * alpha))
		l.draw_circle(p, 2.5, Color(1, 1, 1, alpha))
	else:
		l.draw_circle(p, 3.0, Color(0.1, 0.08, 0.07, alpha))


func _draw_results(l: Node2D, font: Font, at: Vector2) -> void:
	var box := Rect2(at, Vector2(400, 370))
	l.draw_rect(box, Color(0.12, 0.08, 0.06, 0.82))
	var x := box.position.x + 32
	var y := box.position.y + 54
	var perfect := _served.filter(_perfect).size()
	l.draw_string(font, Vector2(x, y), "RESULTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
	l.draw_string(font, Vector2(x, y + 44), "Perfect burgers  %d / %d" % [perfect, _burger_count], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, PERFECT_COL)
	l.draw_string(font, Vector2(x, y + 76), "Seasoned  %d / %d" % [_seasoned_all, _season_total], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.6, 0.9, 0.45))
	for i in _served.size():
		var r: Dictionary = _served[i]
		l.draw_string(font, Vector2(x, y + 106 + i * 26), "Burger %d   %s" % [i + 1, _doneness(r["raw"]) if r["landed"] else "-- dropped"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.7, 0.55))
	var ty := y + 106 + _served.size() * 26 + 12
	l.draw_string(font, Vector2(x, ty), "Perfect %d   Good %d   Miss %d" % [_tally["Perfect"], _tally["Good"], _tally["Miss"]],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.85, 0.85, 0.8))
	l.draw_string(font, Vector2(x, ty + 38), "Score %d   Best x%d" % [score, best_combo], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	l.draw_string(font, Vector2(x, ty + 72), "R to replay  -  Esc for menu", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.8, 0.8))
