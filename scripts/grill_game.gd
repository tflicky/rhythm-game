extends Node2D
## "Grill Master" minigame. One move: flip the burgers.
##
## Call: on a call bar, raw patties drop onto the grill one per note of the bar's
## rhythm -- each lands on its beat with a SIZZLE (left to right across the grate).
## Answer: on the next bar, flip them back in the same rhythm, one SPACE per
## patty. Your tongs flip each one (the flip you drew: grab, toss, land); it lands
## with a quiet sizzle, browns, and hops off onto the picnic table. Miss one and it
## chars and smokes. A press with nothing to flip just clicks the tongs.
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
const SFX_SLOTS := ["flip_cue_2", "flip", "sizzle", "tong"]
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
const COOK_S := 0.35               ## a flipped patty browns over this long
const LEAVE_AFTER := 0.35          ## seconds after landing before it hops off to the table
const LEAVE_S := 0.45              ## the hop to the table
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
}

@export var beatmap: Beatmap

@export_group("Layout")
## Where the patties sit on the grate (screen px, their middles), in the order
## they're called: note 1 of a bar goes on spot 1, and so on.
@export var patty_spots := PackedVector2Array([Vector2(660, 332), Vector2(735, 288), Vector2(810, 332), Vector2(872, 288)])
## Where a cooked patty hops to, on the picnic table (screen px).
@export var table_drop := Vector2(330, 236)
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
var _ui_layer: Node2D              ## practice strip, cards, results: over everything
var _pause: PauseMenu


func _ready() -> void:
	_pause = PauseMenu.attach(self, _restart)   # Esc: Continue / Retry / Quit
	_results = Results.new()
	add_child(_results)
	_back_layer = Node2D.new()
	add_child(_back_layer)
	move_child(_back_layer, _stage.get_index())
	_back_layer.draw.connect(_draw_back)
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
	_home = _stage.position + (DRAWING_AT + _patty_c) * _stage.scale.x
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
	_answers.clear()
	_cycles.clear()
	_fx.clear()
	_flip = {}
	_finished = false
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
		_finished = true
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
	$Field.cameo_on = _phase == Phase.SONG   # the football throw is for the real song only
	if _phase != Phase.CARD or (card_demo and Conductor.playing):
		if _phase == Phase.PRACTICE:
			_judge_practice()
		if _phase == Phase.PRACTICE:
			_schedule_practice()
		var now: float = Conductor.song_position
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
		_drive_patties(Conductor.visual_position)
		_fx = _fx.filter(func(f): return now - f["t0"] < 1.5)
	_drive_tongs(Conductor.visual_position, dt)   # on the card too, so they're there from the start
	_back_layer.queue_redraw()
	_fx_layer.queue_redraw()
	_ui_layer.queue_redraw()


## Stage px from the drawing's own patty to spot `i`.
func _spot_off(i: int) -> Vector2:
	if patty_spots.is_empty():
		return Vector2.ZERO
	return (patty_spots[clampi(i, 0, patty_spots.size() - 1)] - _home) / _stage.scale.x


func _to_stage(screen: Vector2) -> Vector2:
	return (screen - _stage.position) / _stage.scale.x


## Each patty through its life: waiting -> dropping onto the grill (lands on its
## beat) -> raw -> flipping -> cooked -> hops off to the table. Or burnt -> fades.
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
			# a patty still sitting on this spot makes way: off to the table now
			for q in _patties:
				if q != p and q["spot"] == p["spot"] and q["state"] in ["cooked", "burnt", "raw"]:
					q["state"] = "leave" if q["state"] == "cooked" else "gone"
					q["t0"] = vis
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
			"flip":
				var u: float = vis - p["t0"]
				s.position = at
				s.scale = Vector2.ONE
				s.texture = _frames["flip_patty"][_flip_frame(u, p["dur"])]
				if u >= p["dur"]:
					_land(p, vis)
			"cooked":
				var u: float = vis - p["t0"]
				p["mat"].set_shader_parameter("raw", 1.0 - clampf(u / COOK_S, 0.0, 1.0))
				s.position = at
				if u >= LEAVE_AFTER:
					p["state"] = "leave"
					p["t0"] = vis
			"leave":   # a hop over onto the picnic table, shrinking and fading as it goes
				var k := clampf((vis - p["t0"]) / LEAVE_S, 0.0, 1.0)
				var to := _to_stage(table_drop)
				s.position = at.lerp(to, k) + Vector2(0, -160.0 * sin(PI * k))
				s.scale = Vector2.ONE * lerpf(1.0, 0.6, k)
				s.rotation = -TAU * 0.5 * k
				s.modulate.a = 1.0 - smoothstep(0.6, 1.0, k)
				if k >= 1.0:
					p["state"] = "gone"
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


func _land(p: Dictionary, vis: float) -> void:
	p["state"] = "cooked"
	p["t0"] = vis
	var s: Sprite2D = p["sprite"]
	s.texture = _frames["flip_patty"][0]
	s.z_index = 0
	_play("sizzle", -14.0)
	_add_fx("steam", patty_spots[p["spot"]])


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
				if _phase != Phase.SONG:
					_practice_passed = true
					_start_song()
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
	p["t0"] = Conductor.visual_position
	p["dur"] = FLIP_BEATS * Conductor.seconds_per_beat
	# the tongs: the same motion, hurried if the next flip is due before it would end
	var tong_dur: float = p["dur"]
	if not _answers.is_empty():
		tong_dur = clampf(_answers[0]["time"] - a["time"] - 0.03, FLIP_MIN, p["dur"])
	(p["sprite"] as Sprite2D).z_index = 2
	_flip = {"patty": p, "t0": p["t0"], "dur": tong_dur}
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


## Practice shots: a short caption, then a TAP box with a square closing in on
## it that wraps the key exactly when the next burger should be flipped. While a
## burger waits for you, the square pulses.
func _draw_shots(l: Node2D, font: Font) -> void:
	var head := "Try again!" if _shot_retry else "Practice  %d/%d" % [_shot_step + 1, SHOT_PATTERNS.size()]
	var sub := "Sizzle?  Flip it!" if _shot_step == 0 else "Two sizzles?  Flip both, same rhythm!"
	_caption(l, font, sub, head)
	var c: Vector2 = (patty_spots[0] if not patty_spots.is_empty() else VP / 2.0) + Vector2(-40, -150)
	var live := not _answers.is_empty()
	var cap := Rect2(c - Vector2(62, 24), Vector2(124, 48))
	var hot := Color(0.95, 0.55, 0.15)
	l.draw_rect(cap.grow(4), hot if live else Color(hot, 0.4))
	l.draw_rect(cap, Color(1, 0.97, 0.88, 1.0 if live else 0.5))
	l.draw_string(font, Vector2(cap.position.x, cap.position.y + 33), "TAP", HORIZONTAL_ALIGNMENT_CENTER, cap.size.x, 26, Color(INK, 1.0 if live else 0.5))
	l.draw_string(font, Vector2(VP.x - 120, VP.y - 8), "S: skip", HORIZONTAL_ALIGNMENT_RIGHT, 110, 14, Color(INK, 0.45))
	if not live:
		return
	var hug := Vector2(72, 34)         # the square's half-size when it wraps the TAP box
	if _shot_frozen:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * TAU * 2.0)
		var hh := hug + Vector2(6, 6) * pulse
		l.draw_rect(Rect2(c - hh, hh * 2.0), hot, false, 6.0)
		return
	var lead := 2.0 * Conductor.seconds_per_beat   # shows up 2 beats ahead
	var left: float = _answers[0]["time"] + Conductor.input_offset - Conductor.visual_position
	if left > lead or left < -GOOD:
		return
	var k := clampf(left / lead, 0.0, 1.0)
	var h := hug + Vector2(130, 130) * k
	l.draw_rect(Rect2(c - h, h * 2.0), Color(hot, 1.0 - 0.6 * k), false, lerpf(7.0, 3.0, k))


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
