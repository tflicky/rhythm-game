extends Node2D
## "Monkey Business" minigame.
##
## Layout: palm tree on the LEFT, monkey CENTRE-BOTTOM. A fruit appears from
## behind the palm's big front leaves and falls toward the monkey's hands,
## arriving exactly ON the cue beat (LEAD_BEATS of travel, always the same).
##
## The MONKEY is the feedback -- no "Perfect/Good/Miss" text:
##   Perfect -> monkey catches it clean            (monkey_catch)
##   Good    -> bumps off his hands, drops beside  (monkey_bobble + deflected fruit)
##   Miss    -> fruit bonks him on the head        (monkey_hit + stars)
##
## A second monkey (the "twister") stands against the palm trunk in the
## foreground and hip-bumps the tree on every fruit cue sound, shaking it.
##
## Motion is driven by Conductor.visual_position (audio clock + video_offset).
##
## ART: assign the Texture2D slots in the Inspector, or drop PNGs in res://art/
## with the names in AUTO. Empty slots draw placeholder shapes, so you can add
## artwork one piece at a time. See art/README.md.

const LEAD_BEATS := 1.0
## Banana warning taps sound this many beats before each catch (fall is still
## LEAD_BEATS), so the whole tap-tap is heard before the first catch.
const BANANA_CUE_LEAD := 2.0
const PERFECT := 0.075
const GOOD := 0.15
const MISS_TAIL := 0.03    ## seconds past the late edge of GOOD before it's a Miss
const VP := Vector2(1152, 648)
const MONKEY_DUR := {"catch": 0.5, "bobble": 0.6, "hit": 0.75, "clap": 0.25}
const HUD_LEFT := VP.x - 250.0               ## left x of the "SCORE" / "COMBO" readout

## Every resolved fruit: "Perfect", "Good" or "Miss". The level root uses it to
## count practice catches.
signal graded(grade: String)

enum Anchor { CENTER, BOTTOM }

@export_group("Scene anchors")
@export var palm_pos := Vector2(150, 648)     ## palm art, anchored bottom-centre
@export var leaf_spawn := Vector2(250, 150)   ## where the fruit appears (behind the front leaves)
@export var monkey_pos := Vector2(576, 610)   ## monkey art, anchored bottom-centre
@export var hands_offset := Vector2(0, -165)  ## catch point, relative to monkey_pos
@export var head_offset := Vector2(0, -235)   ## bonk point, relative to monkey_pos
@export var you_offset := Vector2(-48, -362)  ## tip of the practice "YOU" arrow, relative to monkey_pos (centred on his head, not the tail-widened art)
@export var deflect_offset := Vector2(60, 200) ## bobbled fruit falls toward here, relative to monkey_pos (his feet); y forced below screen
@export var ground_y := 560.0
## Debug: show the last press's timing error (ms early/late) under COMBO.
@export var show_press_timing := true

@export_group("Art  (empty slot -> placeholder shape)")
@export var art_background: Texture2D
@export var art_ground: Texture2D
@export var art_palm: Texture2D               ## whole palm as one image (used when palm_back/front are empty)
@export var art_palm_back: Texture2D          ## trunk + leaves that sit BEHIND the fruit
@export var art_palm_front: Texture2D         ## the big front fronds, drawn OVER the fruit as it appears
@export var art_coconut: Texture2D
@export var art_banana: Texture2D
@export var art_monkey_idle: Texture2D
@export var art_monkey_catch: Texture2D
@export var art_monkey_catch_banana: Texture2D  ## catch pose specifically for a banana (falls back to art_monkey_catch)
@export var art_monkey_bobble: Texture2D
@export var art_monkey_hit: Texture2D
@export var art_monkey_clap: Texture2D          ## empty-handed press (nothing in the catch window)
@export var art_stars: Texture2D              ## bonk effect for a Miss
@export var art_dust: Texture2D               ## optional puff where a bobbled fruit lands
@export var art_twist_idle: Texture2D         ## twister monkey, resting against the trunk
@export var art_twist_bump: Texture2D         ## twister monkey, hip in the trunk (shown on each fruit cue)

@export_group("Art sizing")
@export var fruit_px := 46.0
@export var palm_scale := 1.0
## Fraction of the single `art_palm` image (from the top) that is leaves/crown --
## that band is redrawn on top so the fruit emerges from behind the fronds.
@export var palm_crown_frac := 0.55
@export var monkey_scale := 1.0

@export_group("Twister monkey (bumps the palm on each cue)")
@export var twist_pos := Vector2(210, 700)    ## bottom-centre of the twister art -- below the screen so his missing legs stay out of frame
@export var twist_scale := 1.4
@export var twist_bump_dur := 0.2            ## seconds he holds the bump pose
@export var palm_shake := 0.035              ## radians the palm rocks when bumped (0 = off)
@export var palm_shake_dur := 0.45

@export_group("Sound  (empty -> silent; or drop files in res://audio/sfx/)")
@export var sfx_cue: AudioStream       ## plays when a fruit leaves the tree (the beat before the catch); banana plays it twice, tap-tap
@export var sfx_catch: AudioStream     ## the coconut thunk
@export var sfx_banana: AudioStream    ## the banana thunk
@export var sfx_volume_db := 0.0
## Extra gain on the fruit cue so it cuts through the music. Sound effects run
## through an "SFX" bus with a limiter, so boosting past 0 dB won't clip.
@export var sfx_cue_db := 4.0
## Count-in before the first fruit: "3, 2, 1, GO!" on the beats before its cue.
@export var count_in := true
@export var count_in_db := 0.0
## Pitch multiplier for the banana's tap-tap warning (1.0 = same as coconut).
@export var banana_cue_pitch := 1.5
## With no sfx_banana, the banana catch reuses the coconut thunk at this pitch
## so it's never silent. Ignored once a real banana sound is assigned.
@export var banana_catch_pitch := 1.6
## true: the thunk is pre-scheduled to land exactly on the cue's beat, for every
## fruit (the monkey shows catch/bobble/miss). false: it plays reactively on the
## keypress, only on a clean Perfect -- tight to your input but ~1 frame + audio
## latency behind the beat.
@export var sfx_catch_on_beat := true

const ART_DIR := "res://art/"
const IMG_EXT := ["png", "webp", "jpg", "jpeg", "svg", "bmp"]
const AUTO := {
	"art_background": "background.png", "art_ground": "ground.png",
	"art_palm": "palm_tree.png",
	"art_palm_back": "palm_back.png", "art_palm_front": "palm_front.png",
	"art_coconut": "coconut.png", "art_banana": "banana.png",
	"art_monkey_idle": "monkey_idle.png", "art_monkey_catch": "monkey_catch.png",
	"art_monkey_catch_banana": "monkey_catch_banana.png",
	"art_monkey_bobble": "monkey_bobble.png", "art_monkey_hit": "monkey_hit.png",
	"art_monkey_clap": "monkey_clap.png",
	"art_twist_idle": "monkey_twist_0.png", "art_twist_bump": "monkey_twist_1.png",
	"art_stars": "stars.png", "art_dust": "dust.png",
}
const SFX_DIR := "res://audio/sfx/"
const SFX_EXT := ["wav", "ogg", "mp3"]
const SFX_AUTO := {"sfx_cue": "cue", "sfx_catch": "catch", "sfx_banana": "banana"}

var cues: Array = []
var _next := 0                     ## next cue in cues[] to spawn
var _falling: Array = []           ## [{ cue, spawn_t, sfx_done }] -- fruits in the air, oldest first
var _fx: Array = []                ## deflect / bonk_star / bonk_fall, outliving the fruit
var _warn_next := 0                ## next cue in cues[] whose warning hasn't been handled
var _pending_tap2_at := -1.0       ## song_position to fire the banana's 2nd tap, or -1

var score := 0
var combo := 0
var best_combo := 0
var _tally := {"Perfect": 0, "Good": 0, "Miss": 0}
var _monkey_state := "idle"
var _monkey_fruit := ""
var _monkey_state_t := -10.0
var _bump_t := -10.0               ## song time the latest cue sound is heard -- twister bump + palm shake
var _finished := false
var _last_press := ""

## Practice round (driven by rhythm.gd): shows "YOU" over the catcher, the
## instructions and a catch counter instead of the score HUD.
var practice := false
var practice_caught := 0
var practice_goal := 3
var banner := ""                   ## big centred message, e.g. between practice and the song
@onready var _panel_sb := _panel_style()

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _mbbox := {}   ## monkey Texture2D -> Rect2 of its opaque pixels, for size-normalising poses
var _count: Array = []             ## count-in: [{ beat, text, heard }] -- see _build_count_in
var _tick: AudioStreamWAV


func _ready() -> void:
	# Match every file found anywhere under res://art/ and res://audio/sfx/ to a
	# slot by name -- tolerating subfolders and doubled extensions.
	var art_found := _scan_dir(ART_DIR, IMG_EXT)
	var art_n := 0
	for prop in AUTO:
		if get(prop) != null:
			art_n += 1
			continue
		var stem: String = (AUTO[prop] as String).get_basename()
		if art_found.has(stem):
			set(prop, load(art_found[stem]))
			art_n += 1

	var sfx_found := _scan_dir(SFX_DIR, SFX_EXT)
	var sfx_n := 0
	for prop in SFX_AUTO:
		if get(prop) == null and sfx_found.has(SFX_AUTO[prop]):
			set(prop, load(sfx_found[SFX_AUTO[prop]]))
		if get(prop) != null:
			sfx_n += 1
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = _sfx_bus()
		add_child(p)
		_sfx_players.append(p)

	# Cache the opaque bounding box of every monkey pose so poses drawn on
	# different-sized canvases still render at a consistent on-screen size.
	for t in [art_monkey_idle, art_monkey_catch, art_monkey_catch_banana, art_monkey_bobble, art_monkey_hit, art_monkey_clap]:
		if t and not _mbbox.has(t):
			_mbbox[t] = _opaque_bbox(t)

	print("[coconut] art %d/%d, sfx %d/%d" % [art_n, AUTO.size(), sfx_n, SFX_AUTO.size()])


func _opaque_bbox(tex: Texture2D) -> Rect2:
	var img := tex.get_image()
	if img == null:
		return Rect2(Vector2.ZERO, tex.get_size())
	var r := img.get_used_rect()
	return Rect2(r) if r.size != Vector2i.ZERO else Rect2(Vector2.ZERO, tex.get_size())


## Uses ResourceLoader.list_directory, not DirAccess: in an exported game the
## folders hold only *.import stubs (the PNGs/WAVs themselves aren't packed),
## so a plain directory listing finds nothing there.
func _scan_dir(dir_path: String, exts: Array) -> Dictionary:
	var out := {}
	for entry in ResourceLoader.list_directory(dir_path):
		var full := dir_path.path_join(entry.trim_suffix("/"))
		if entry.ends_with("/"):
			if not entry.begins_with("."):
				out.merge(_scan_dir(full, exts), true)
			continue
		var stem := entry
		while stem.get_extension().to_lower() in exts:
			stem = stem.get_basename()
		if stem != entry and ResourceLoader.exists(full):
			out[stem] = full
	return out


func _play(stream: AudioStream, pitch := 1.0, gain_db := 0.0) -> void:
	if stream == null or _sfx_players.is_empty():
		return
	var p := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = stream
	p.volume_db = sfx_volume_db + gain_db
	p.pitch_scale = pitch
	p.play()


func _play_catch(fruit: String) -> void:
	if fruit != "banana":
		_play(sfx_catch)
	elif sfx_banana:
		_play(sfx_banana)
	else:
		_play(sfx_catch, banana_catch_pitch)


func begin(compiled_cues: Array) -> void:
	cues = compiled_cues
	_next = 0
	_falling.clear()
	_fx.clear()
	_warn_next = 0
	_pending_tap2_at = -1.0
	score = 0
	combo = 0
	best_combo = 0
	_tally = {"Perfect": 0, "Good": 0, "Miss": 0}
	_monkey_state = "idle"
	_bump_t = -10.0
	_monkey_fruit = ""
	_finished = false
	_last_press = ""
	_build_count_in()
	if not Conductor.song_finished.is_connected(_on_finished):
		Conductor.song_finished.connect(_on_finished)
	set_process(true)
	queue_redraw()


func _process(_dt: float) -> void:
	if cues.is_empty():
		return
	var now: float = Conductor.song_position
	var spb: float = Conductor.seconds_per_beat

	var latency: float = AudioServer.get_output_latency()

	# Count-in ticks, fired output-latency early like the cue so they land on the beat.
	for c in _count:
		if not c["heard"] and now >= Conductor.time_of_beat(c["beat"]) - latency:
			c["heard"] = true
			_play(_tick, 1.5 if c["text"] == "GO!" else 1.0, count_in_db)

	# Warning tap(s), fired output-latency early so the audible "plonk" lands
	# exactly LEAD_BEATS before the catch -- same trick as the thunk below.
	# Decoupled from fruit spawning (which stays on the unshifted beat) since
	# audio has to clear the mixer/driver pipeline before it's heard, but the
	# visual can appear the instant the clock crosses the mark.
	while _warn_next < cues.size():
		var wi := _warn_next
		var nc: Dictionary = cues[wi]
		var cue_lead: float = BANANA_CUE_LEAD if nc["cue"] == "banana" else LEAD_BEATS
		if now < nc["time"] - cue_lead * spb - latency:
			break
		_warn_next += 1
		# A banana pair is two adjacent cues -- only the first plays a cue at
		# all (the tap-tap warns "two coming"); the second spawns silently.
		var is_second_banana: bool = nc["cue"] == "banana" and wi > 0 \
			and cues[wi - 1]["cue"] == "banana"
		if not is_second_banana:
			_play(sfx_cue, banana_cue_pitch if nc["cue"] == "banana" else 1.0, sfx_cue_db)
			_bump_t = nc["time"] - cue_lead * spb
			_pending_tap2_at = -1.0
			if nc["cue"] == "banana" and wi + 1 < cues.size() \
					and cues[wi + 1]["cue"] == "banana":
				# Match the warning's tap-tap to the ACTUAL gap between the two
				# catch beats (up to banana_gap, whatever was recorded), not a
				# fixed eighth note -- the second tap is scheduled the same way
				# as the first: output-latency early, BANANA_CUE_LEAD before ITS catch.
				_pending_tap2_at = cues[wi + 1]["time"] - BANANA_CUE_LEAD * spb - latency

	# Banana gets a second cue tap shortly after the first, so the warning itself
	# reads as a double-tap (distinct from a single coconut tap).
	if _pending_tap2_at >= 0.0 and now >= _pending_tap2_at:
		_pending_tap2_at = -1.0
		_play(sfx_cue, banana_cue_pitch, sfx_cue_db)
		_bump_t = now + latency

	# Every fruit spawns on its own schedule, even while an earlier one is still in
	# the air (a banana pair overlaps: #2 leaves the tree as #1 reaches the hands).
	while _next < cues.size():
		var c: Dictionary = cues[_next]
		var spawn_t: float = c["time"] - LEAD_BEATS * spb
		if now < spawn_t:
			break
		_falling.append({"cue": c, "spawn_t": spawn_t, "sfx_done": false})
		_next += 1

	for i in range(_falling.size() - 1, -1, -1):
		var f: Dictionary = _falling[i]
		# The thunk, pre-scheduled onto the cue's beat. Fire it output-latency early
		# so it leaves the speakers exactly when the music reaches the beat.
		if sfx_catch_on_beat and not f["sfx_done"] and now >= f["cue"]["time"] - latency:
			f["sfx_done"] = true
			_play_catch(f["cue"]["cue"])
		# Miss only once the whole Good window (measured against the player's own
		# input latency) has passed -- so the fruit is still catchable while it
		# looks like it's in his hands.
		if now > f["cue"]["time"] + Conductor.input_offset + GOOD + MISS_TAIL:
			_bonk(f)
			_resolve(f, "Miss")

	if _monkey_state != "idle" and now - _monkey_state_t > MONKEY_DUR[_monkey_state]:
		_monkey_state = "idle"

	for i in range(_fx.size() - 1, -1, -1):
		if now > _fx[i]["t0"] + _fx[i]["dur"]:
			_fx.remove_at(i)

	queue_redraw()


func _unhandled_input(e: InputEvent) -> void:
	var pressed: bool = e.is_action_pressed("ui_accept") \
		or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) \
		or (e is InputEventScreenTouch and e.pressed)
	if not pressed:
		return
	if _falling.is_empty():
		_log_press("no fruit falling", 0.0)
		_set_monkey("clap")
		return
	# Grade against whichever fruit in the air this press is closest to.
	var f: Dictionary = {}
	var err := INF
	for cand in _falling:
		var e2: float = Conductor.timing_error(cand["cue"]["beat"])   # input-latency compensated
		if absf(e2) < absf(err):
			err = e2
			f = cand
	var fruit: String = f["cue"]["cue"]
	if absf(err) > GOOD:
		_log_press("ignored (%s)" % fruit, err)
		_set_monkey("clap")
		return  # out of the window -- he just claps; no catch, no sound, the fruit carries on
	_log_press(("Perfect" if absf(err) <= PERFECT else "Good") + " (%s)" % fruit, err)
	if absf(err) <= PERFECT:
		if not sfx_catch_on_beat:
			_play_catch(fruit)
		_set_monkey("catch", fruit)
		_resolve(f, "Perfect")
	else:
		_set_monkey("bobble", fruit)
		_deflect(fruit)
		_resolve(f, "Good")


## Prints every press with its timing error, and shows the last one in the HUD,
## so a "that should've counted" moment can be checked against the numbers.
func _log_press(what: String, err: float) -> void:
	if what == "no fruit falling":
		_last_press = what
	else:
		_last_press = "%s  %+.0f ms %s" % [what, err * 1000.0, "late" if err > 0.0 else "early"]
	print("[press] beat %.2f  %s" % [Conductor.song_position_in_beats, _last_press])


func _resolve(f: Dictionary, grade: String) -> void:
	var fruit: String = f["cue"]["cue"]
	_tally[grade] += 1
	if grade == "Miss":
		combo = 0
	else:
		combo += 1
		best_combo = maxi(best_combo, combo)
		score += (100 if grade == "Perfect" else 50) + (20 if fruit == "banana" else 0)
	_falling.erase(f)
	graded.emit(grade)


func _set_monkey(state: String, fruit := "") -> void:
	_monkey_state = state
	_monkey_fruit = fruit
	_monkey_state_t = Conductor.song_position


func _deflect(fruit: String) -> void:
	# bumps off his hands and drops past his feet, off the bottom -- not flung away
	var target := monkey_pos + deflect_offset
	target.y = maxf(target.y, VP.y + 140.0)
	_fx.append({"kind": "deflect", "t0": Conductor.song_position, "dur": 0.7,
		"fruit": fruit, "from": _hands(), "to": target, "spin": 1.3})


func _bonk(f: Dictionary) -> void:
	_set_monkey("hit")
	var now := Conductor.song_position
	_fx.append({"kind": "bonk_star", "t0": now, "dur": 0.45})
	# small arc off his head toward the COMBO readout, then falls off the bottom
	_fx.append({"kind": "bonk_fall", "t0": now, "dur": 0.9, "fruit": f["cue"]["cue"],
		"from": _fall_pos(_fall_u(f, Conductor.visual_position)), "land": Vector2(HUD_LEFT, ground_y)})


func _on_finished() -> void:
	if practice:
		return   # rhythm.gd loops the song; no results screen mid-practice
	_finished = true
	queue_redraw()


# --- geometry ------------------------------------------------------------------

func _hands() -> Vector2:
	return monkey_pos + hands_offset

func _head() -> Vector2:
	return monkey_pos + head_offset

## Continuous fruit path. u = 0 at the leaves, u = 1 at the hands (the catch
## moment). u > 1 keeps accelerating straight down past the head and off screen --
## one unbroken motion, no clamp, no pause.
func _fall_pos(u: float) -> Vector2:
	var h := _hands()
	if u <= 1.0:
		return leaf_spawn.lerp(h, pow(u, 1.3))   # gentle acceleration from off-screen
	var over := u - 1.0
	return h + Vector2(over * 60.0, over * 300.0 + over * over * 850.0)


## Fall progress of fruit f at visual time t: 0 at spawn, 1 at the hands.
func _fall_u(f: Dictionary, t: float) -> float:
	var sp: float = f["spawn_t"]
	var arrive: float = f["cue"]["time"] + Conductor.input_offset + Conductor.video_offset
	return maxf(t - sp, 0.0) / maxf(arrive - sp, 0.0001)


# --- drawing -----------------------------------------------------------------

func _draw() -> void:
	_draw_background()

	var now := Conductor.visual_position

	# The palm rocks around its base when the twister bumps it. Palm layers are
	# drawn relative to palm_pos under this transform.
	var two_layer_palm := art_palm_back != null or art_palm_front != null
	_palm_transform(now)
	if art_palm_back:
		_blit(art_palm_back, Vector2.ZERO, palm_scale, Anchor.BOTTOM)
	elif art_palm:
		_blit(art_palm, Vector2.ZERO, palm_scale, Anchor.BOTTOM)   # whole tree, one layer
	elif not two_layer_palm:
		_draw_palm_back()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# The falling fruit reaches the hands the moment a perfectly-timed press
	# REGISTERS (cue.time shifted by the player's input latency), so what you see
	# and when you should click line up. It never clamps or pauses -- if missed,
	# a "bonk_fall" fx takes over from the exact same position (arc off the head).
	# Layer order: monkeys < falling fruit < palm crown. The fruit is always BEHIND
	# the fronds (it emerges from them, never pops through) and always IN FRONT of
	# the monkeys (it lands in the catcher's hands). The crown sits above both
	# monkeys, so the two never overlap.
	for f in _falling:
		var fu := _fall_u(f, now)
		if fu < 1.0:
			draw_circle(Vector2(_fall_pos(fu).x, ground_y + 6), 10.0 + fu * 14.0,
				Color(0, 0, 0, 0.12 * clampf(fu * 3.0, 0.0, 1.0)))

	_draw_twister(now)
	_draw_monkey()
	if practice:
		_draw_you_label()   # under the fruit, so a coconut passes in front of it

	for f in _falling:
		var fu := _fall_u(f, now)
		_draw_fruit(_fall_pos(fu), 1.0, f["cue"]["cue"], maxf(0.0, fu - 1.0) * 4.0)

	_palm_transform(now)
	if art_palm_front:
		_blit(art_palm_front, Vector2(60, -320), palm_scale, Anchor.CENTER)
	elif art_palm:
		# redraw the top band of the single palm image on top, so the fruit
		# emerges from behind the fronds
		var ps: Vector2 = art_palm.get_size()
		var dst: Vector2 = ps * palm_scale
		var tl := -Vector2(dst.x * 0.5, dst.y)
		draw_texture_rect_region(art_palm,
			Rect2(tl, Vector2(dst.x, dst.y * palm_crown_frac)),
			Rect2(Vector2.ZERO, Vector2(ps.x, ps.y * palm_crown_frac)))
	else:
		_draw_palm_front()   # placeholder fronds
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_fx(now)
	_draw_count_in(now)
	if practice:
		_draw_practice()
	else:
		_draw_hud()
	if banner != "":
		_draw_banner()
	if _finished:
		_draw_results()


func _draw_fx(now: float) -> void:
	for f in _fx:
		var t: float = (now - f["t0"]) / f["dur"]
		match f["kind"]:
			"deflect":
				# bumps off his hands, small spin, drops past his feet off the bottom
				var from: Vector2 = f["from"]
				var to: Vector2 = f["to"]
				var k := clampf(t, 0.0, 1.0)
				var pos := from.lerp(to, k)
				pos.y -= sin(k * PI) * 55.0          # small bump off the hands
				_draw_fruit(pos, 1.0, f["fruit"], t * f["spin"])
			"bonk_fall":
				# small arc off his head toward the COMBO readout, then keeps
				# falling straight down and off the bottom of the screen
				var bfrom: Vector2 = f["from"]
				var bland: Vector2 = f["land"]
				var hop := 0.45
				var bpos: Vector2
				if t < hop:
					var k := t / hop
					bpos = bfrom.lerp(bland, k)
					bpos.y -= sin(k * PI) * 80.0
				else:
					var fd: float = (t - hop) * float(f["dur"])
					bpos = Vector2(bland.x + fd * 40.0, bland.y + fd * fd * 2200.0)
				_draw_fruit(bpos, 1.0, f["fruit"], minf(t / hop, 1.0) * 3.0)
			"bonk_star":
				if art_stars:
					_blit(art_stars, _head() + Vector2(0, -6), 0.6 + t * 0.6,
						Anchor.CENTER, Color(1, 1, 1, clampf(1.0 - t, 0.0, 1.0)))
				else:
					for i in 5:
						var ang := TAU * i / 5.0 + t * 3.0
						var r := 10.0 + t * 34.0
						draw_circle(_head() + Vector2(cos(ang), sin(ang)) * r,
							3.5 * (1.0 - t), Color(1, 0.95, 0.4, 1.0 - t))


# --- element renderers (texture, else placeholder) ---------------------------

func _blit(tex: Texture2D, at: Vector2, scale: float, anchor: int, mod := Color.WHITE) -> void:
	var sz: Vector2 = tex.get_size() * scale
	var oy: float = sz.y * 0.5 if anchor == Anchor.CENTER else sz.y
	draw_texture_rect(tex, Rect2(at - Vector2(sz.x * 0.5, oy), sz), false, mod)


func _blit_or(tex: Texture2D, at: Vector2, scale: float, anchor: int, fallback: Callable) -> void:
	if tex:
		_blit(tex, at, scale, anchor)
	else:
		fallback.call()


func _draw_background() -> void:
	if art_background:
		draw_texture_rect(art_background, Rect2(Vector2.ZERO, VP), false)
	else:
		draw_rect(Rect2(Vector2.ZERO, VP), Color(0.53, 0.79, 0.92))
		draw_rect(Rect2(0, ground_y, VP.x, VP.y - ground_y), Color(0.93, 0.85, 0.62))
	if art_ground:
		draw_texture_rect(art_ground, Rect2(0, ground_y, VP.x, VP.y - ground_y), false)


## Seconds since the latest bump was heard, or -1 if none is in progress.
func _bump_elapsed(now: float, dur: float) -> float:
	var e := now - _bump_t
	return e if e >= 0.0 and e < dur else -1.0


## Rotate subsequent draws around the palm's base; rocks back and forth after a bump.
func _palm_transform(now: float) -> void:
	var angle := 0.0
	var e := _bump_elapsed(now, palm_shake_dur)
	if e >= 0.0:
		var k := e / palm_shake_dur
		angle = -palm_shake * sin(k * TAU * 1.5) * (1.0 - k)   # first push away from the twister
	draw_set_transform(palm_pos, angle, Vector2.ONE)


func _draw_twister(now: float) -> void:
	var tex := art_twist_bump if (_bump_elapsed(now, twist_bump_dur) >= 0.0 and art_twist_bump) else art_twist_idle
	if tex:
		_blit(tex, twist_pos, twist_scale, Anchor.BOTTOM)


# placeholder palm, drawn relative to palm_pos (see _palm_transform)
func _draw_palm_back() -> void:
	draw_line(Vector2(0, ground_y - palm_pos.y), Vector2(30, -470),
		Color(0.5, 0.34, 0.2), 22.0)


func _draw_palm_front() -> void:
	var crown := Vector2(30, -470)
	for a in [-2.6, -1.9, -1.2, -0.5, 0.1, 0.7]:
		draw_line(crown, crown + Vector2(cos(a), sin(a)).normalized() * 150.0, Color(0.13, 0.5, 0.26), 16.0)


func _draw_monkey() -> void:
	var tex: Texture2D = art_monkey_idle
	match _monkey_state:
		"catch":
			tex = art_monkey_catch_banana if (_monkey_fruit == "banana" and art_monkey_catch_banana) else art_monkey_catch
		"bobble":
			tex = art_monkey_bobble
		"hit":
			tex = art_monkey_hit
		"clap":
			tex = art_monkey_clap
	if tex == null:
		tex = art_monkey_idle

	var k := 0.0
	if _monkey_state != "idle":
		k = clampf(1.0 - (Conductor.visual_position - _monkey_state_t) / MONKEY_DUR[_monkey_state], 0.0, 1.0)
	var origin := monkey_pos
	var angle := 0.0
	var squash := Vector2.ONE
	match _monkey_state:
		"catch":
			squash = Vector2(1.0 - 0.05 * k, 1.0 + 0.09 * k)
		"bobble":
			origin += Vector2(sin(k * 34.0) * 7.0, 0.0)
		"hit":
			angle = -0.24 * k
			origin += Vector2(-12.0 * k, -4.0 * k)
		"clap":
			squash = Vector2(1.0 + 0.06 * k, 1.0 - 0.06 * k)   # quick squish on the clap

	if tex:
		# Normalise by the pose's opaque width so different-sized canvases render
		# the monkey at a consistent size, and anchor the opaque bbox's
		# bottom-centre at monkey_pos.
		var bb: Rect2 = _mbbox.get(tex, Rect2(Vector2.ZERO, tex.get_size()))
		var ref: Rect2 = _mbbox.get(art_monkey_idle, bb)
		var norm: float = (ref.size.x / bb.size.x) if bb.size.x > 0.0 else 1.0
		draw_set_transform(origin, angle, squash * (monkey_scale * norm))
		var tl := -Vector2(bb.position.x + bb.size.x * 0.5, bb.position.y + bb.size.y)
		draw_texture_rect(tex, Rect2(tl, tex.get_size()), false)
	else:
		draw_set_transform(origin, angle, squash * monkey_scale)
		_draw_monkey_placeholder()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_monkey_placeholder() -> void:
	# drawn around a bottom-centre origin (feet at 0,0)
	draw_circle(Vector2(0, -34), 32.0, Color(0.4, 0.28, 0.2))         # body
	draw_circle(Vector2(0, -78), 22.0, Color(0.45, 0.32, 0.23))       # head
	draw_circle(Vector2(-21, -90), 8.0, Color(0.45, 0.32, 0.23))
	draw_circle(Vector2(21, -90), 8.0, Color(0.45, 0.32, 0.23))
	draw_circle(Vector2(0, -74), 13.0, Color(0.86, 0.73, 0.56))       # face
	var arm := Color(0.4, 0.28, 0.2)
	match _monkey_state:
		"catch":
			draw_line(Vector2(-14, -46), Vector2(-6, -70), arm, 9.0)
			draw_line(Vector2(14, -46), Vector2(6, -70), arm, 9.0)
		"bobble":
			draw_line(Vector2(-14, -46), Vector2(-40, -60), arm, 9.0)
			draw_line(Vector2(14, -46), Vector2(40, -60), arm, 9.0)
		"hit":
			draw_line(Vector2(-14, -46), Vector2(-34, -30), arm, 9.0)
			draw_line(Vector2(14, -46), Vector2(34, -30), arm, 9.0)
		"clap":
			draw_line(Vector2(-14, -46), Vector2(-2, -84), arm, 9.0)
			draw_line(Vector2(14, -46), Vector2(2, -84), arm, 9.0)
		_:
			draw_line(Vector2(-14, -44), Vector2(-24, -66), arm, 9.0)
			draw_line(Vector2(14, -44), Vector2(24, -66), arm, 9.0)


func _draw_fruit(pos: Vector2, a: float, kind: String, rot := 0.0) -> void:
	var tex: Texture2D = art_banana if kind == "banana" else art_coconut
	if tex:
		var sz: Vector2 = tex.get_size() * (fruit_px / maxf(tex.get_size().x, 1.0))
		draw_set_transform(pos, rot, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-sz * 0.5, sz), false, Color(1, 1, 1, a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif kind == "banana":
		draw_arc(pos + Vector2(0, 8), 22.0, deg_to_rad(35), deg_to_rad(145), 20, Color(0.98, 0.82, 0.2, a), 11.0)
		draw_arc(pos + Vector2(0, 8), 22.0, deg_to_rad(35), deg_to_rad(145), 20, Color(1, 0.92, 0.55, a), 4.0)
	else:
		draw_circle(pos, 18.0, Color(0.32, 0.2, 0.12, a))
		draw_circle(pos + Vector2(-5, -5), 4.0, Color(0.55, 0.4, 0.26, a))


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(HUD_LEFT, 52), "SCORE  %d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.15, 0.15, 0.2))
	draw_string(font, Vector2(HUD_LEFT, 88), "COMBO  x%d" % combo, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.15, 0.15, 0.2))
	if show_press_timing and _last_press != "":
		draw_string(font, Vector2(HUD_LEFT, 116), _last_press, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.15, 0.15, 0.2))


func _draw_results() -> void:
	var font := ThemeDB.fallback_font
	var box := Rect2(VP.x / 2 - 200, VP.y / 2 - 120, 400, 240)
	draw_rect(box, Color(0, 0, 0, 0.6))
	var x := box.position.x + 32
	var y := box.position.y + 54
	draw_string(font, Vector2(x, y), "RESULTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
	draw_string(font, Vector2(x, y + 50), "Caught    %d" % _tally["Perfect"], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.7, 1.0, 0.6))
	draw_string(font, Vector2(x, y + 82), "Bobbled   %d" % _tally["Good"], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.9, 0.5))
	draw_string(font, Vector2(x, y + 114), "Bonked    %d" % _tally["Miss"], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.5, 0.5))
	draw_string(font, Vector2(x, y + 154), "Score %d   Best x%d" % [score, best_combo], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
	draw_string(font, Vector2(x, y + 186), "R to replay  -  Esc for menu", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.8, 0.8))


# --- practice round ----------------------------------------------------------

## Drop every cue that hasn't been heard yet, so nothing new falls. A fruit whose
## cue sound already played still comes down.
func stop_spawning() -> void:
	cues = cues.slice(0, maxi(_next, _warn_next))


func _outlined(font: Font, pos: Vector2, text: String, size: int, color: Color, width := -1.0) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, 8, Color(0.15, 0.1, 0.08))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


func _draw_you_label() -> void:
	var font := ThemeDB.fallback_font
	var tip := monkey_pos + you_offset
	var w := 200.0
	_outlined(font, Vector2(tip.x - w * 0.5, tip.y - 40), "YOU", 44, Color(1, 0.95, 0.45), w)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(-13, -30), tip + Vector2(13, -30), tip]),
		Color(1, 0.95, 0.45))


func _draw_practice() -> void:
	var font := ThemeDB.fallback_font
	var box := Rect2(VP.x - 400, 24, 376, 282)
	var ink := Color(0.2, 0.14, 0.12)
	var x := box.position.x
	var y := box.position.y
	var w := box.size.x
	draw_style_box(_panel_sb, box)
	draw_string(font, Vector2(x, y + 48), "PRACTICE", HORIZONTAL_ALIGNMENT_CENTER, w, 34, ink)
	draw_string(font, Vector2(x, y + 86), "Listen for the cue sound,", HORIZONTAL_ALIGNMENT_CENTER, w, 22, ink)
	draw_string(font, Vector2(x, y + 114), "then press SPACEBAR to catch", HORIZONTAL_ALIGNMENT_CENTER, w, 22, ink)
	draw_string(font, Vector2(x, y + 142), "the coconut on the beat!", HORIZONTAL_ALIGNMENT_CENTER, w, 22, ink)
	draw_string(font, Vector2(x, y + 266), "Press S to skip practice", HORIZONTAL_ALIGNMENT_CENTER, w, 18, Color(ink, 0.6))
	# one coconut per catch needed; filled in as they're caught
	var r := 16.0
	var icon := 64.0   ## on-screen diameter of a caught coconut
	var gap := 84.0
	var cx := x + w * 0.5 - gap * (practice_goal - 1) * 0.5
	for i in practice_goal:
		var c := Vector2(cx + gap * i, y + 202)
		if i < practice_caught:
			if art_coconut:
				# crop to the coconut itself -- the PNG has a lot of empty margin
				if not _mbbox.has(art_coconut):
					_mbbox[art_coconut] = _opaque_bbox(art_coconut)
				var src: Rect2 = _mbbox[art_coconut]
				var sz := src.size * (icon / maxf(src.size.x, 1.0))
				draw_texture_rect_region(art_coconut, Rect2(c - sz * 0.5, sz), src)
			else:
				draw_circle(c, r, Color(0.45, 0.28, 0.14))
		else:
			draw_arc(c, r, 0.0, TAU, 32, Color(0.2, 0.14, 0.12, 0.45), 3.0)


func _draw_banner() -> void:
	var font := ThemeDB.fallback_font
	_outlined(font, Vector2(0, VP.y * 0.42), banner, 56, Color.WHITE, VP.x)


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(1, 0.97, 0.88, 0.92)
	s.set_corner_radius_all(18)
	s.set_border_width_all(4)
	s.border_color = Color(0.2, 0.14, 0.12)
	return s


# --- count-in & sound bus ----------------------------------------------------

## "3, 2, 1, GO!" on the four beats before the first fruit's cue sound, so the
## player knows exactly when it starts. Beats before the song starts are dropped.
func _build_count_in() -> void:
	_count.clear()
	if not count_in or practice or cues.is_empty():   # the song only; practice has its metronome
		return
	if _tick == null:
		_tick = _make_tick()
	var first: Dictionary = cues[0]
	var heard: float = first["beat"] - (BANANA_CUE_LEAD if first["cue"] == "banana" else LEAD_BEATS)
	var words := ["3", "2", "1", "GO!"]
	for i in words.size():
		var b := heard - float(words.size() - i)
		if b >= 0.0:
			_count.append({"beat": b, "text": words[i], "heard": false})


func _draw_count_in(now: float) -> void:
	for c in _count:
		var t0 := Conductor.time_of_beat(c["beat"])
		var k := (now - t0) / Conductor.seconds_per_beat   # 0..1 across its beat
		if k < 0.0 or k >= 1.0:
			continue
		var font := ThemeDB.fallback_font
		var size := int(lerpf(110.0, 84.0, minf(k * 4.0, 1.0)))   # pops in, settles
		var col := Color(1, 0.95, 0.45, clampf((1.0 - k) * 3.0, 0.0, 1.0))
		draw_string_outline(font, Vector2(0, VP.y * 0.32), c["text"], HORIZONTAL_ALIGNMENT_CENTER, VP.x, size, 12, Color(0.15, 0.1, 0.08, col.a))
		draw_string(font, Vector2(0, VP.y * 0.32), c["text"], HORIZONTAL_ALIGNMENT_CENTER, VP.x, size, col)


## Short woodblock-ish tick for the count-in, so it needs no audio file.
func _make_tick() -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * 0.08)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := pow(1.0 - float(i) / n, 4.0)
		var s := (sin(TAU * 880.0 * t) * 0.7 + sin(TAU * 1760.0 * t) * 0.3) * env * 0.8
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


## "SFX" bus with a hard limiter, so boosted sounds (sfx_cue_db) get louder
## without clipping. Created once at runtime; the audio server keeps it.
func _sfx_bus() -> StringName:
	if AudioServer.get_bus_index(&"SFX") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, &"SFX")
		AudioServer.set_bus_send(idx, &"Master")
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.3
		AudioServer.add_bus_effect(idx, lim)
	return &"SFX"
