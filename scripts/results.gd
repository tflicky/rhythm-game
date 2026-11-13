class_name Results
extends Node
## Every level's results number: just the percent you got. It counts up from 0
## (fast, then slowing near the end) over a drum roll, waits half a beat, then
## swells toward you and slams back down. Its colour goes from red (0%) through
## a reddish yellow (50%) to green (100%) as it counts.
##
## Each level adds one of these as a child, calls draw_percent() from its own
## drawing every frame the results are up (the count starts on the first call),
## and reset() when the level restarts.
##
## The drum roll is your sound: res://audio/sfx/drum_roll.wav (or .ogg / .mp3).
## Until that file exists a plain synth roll stands in.

const RED := Color(0.9, 0.15, 0.1)
const MID := Color(0.95, 0.6, 0.1)
const GREEN := Color(0.25, 0.8, 0.3)

const ROLL_PATH := "res://audio/sfx/drum_roll"
const COUNT_MIN := 0.6        ## seconds to count to 0%...
const COUNT_MAX := 2.2        ## ...and to 100% (in between: in proportion)
const RISE := 0.22            ## the number swelling up toward you
const SLAM := 0.1             ## ...and slamming back down
const SETTLE := 0.4           ## the squash + shake dying away after the slam
const BIG := 1.8              ## how big it gets at the top of the swell
const FONT_SIZE := 84

var _t0 := -1                 ## ticks (ms) when the results appeared; -1 = not yet
var _pct := 0
var _ci: CanvasItem           ## who draws us (kept redrawing while we animate)
var _roll: AudioStreamPlayer


## 0..100, rounded. 0 when there was nothing to get.
static func percent(got: int, total: int) -> int:
	return roundi(100.0 * got / total) if total > 0 else 0


## The colour for `k` = 0..1.
static func pct_color(k: float) -> Color:
	k = clampf(k, 0.0, 1.0)
	return RED.lerp(MID, k * 2.0) if k < 0.5 else MID.lerp(GREEN, (k - 0.5) * 2.0)


func _ready() -> void:
	_roll = AudioStreamPlayer.new()
	add_child(_roll)
	for ext in ["wav", "ogg", "mp3"]:
		if ResourceLoader.exists("%s.%s" % [ROLL_PATH, ext]):
			_roll.stream = load("%s.%s" % [ROLL_PATH, ext])
			break
	if _roll.stream == null:
		_roll.stream = _synth_roll(COUNT_MAX)
	_roll.volume_db = -6.0


## Back to "not shown yet" (call when the level restarts).
func reset() -> void:
	_t0 = -1
	_roll.stop()


func _count_time() -> float:
	return lerpf(COUNT_MIN, COUNT_MAX, _pct / 100.0)


func _half_beat() -> float:
	return 0.5 * (Conductor.seconds_per_beat if Conductor.seconds_per_beat > 0.0 else 0.5)


func _process(_dt: float) -> void:
	if _t0 < 0:
		return
	var t := (Time.get_ticks_msec() - _t0) / 1000.0
	if _roll.playing and t >= _count_time():
		_roll.stop()                      # the roll ends right as the count lands
	if t < _count_time() + _half_beat() + RISE + SLAM + SETTLE + 0.1 and is_instance_valid(_ci):
		_ci.queue_redraw()


## Draw the percent centred on `center`. The first call starts the count.
func draw_percent(ci: CanvasItem, font: Font, center: Vector2, got: int, total: int) -> void:
	_ci = ci
	if _t0 < 0:
		_t0 = Time.get_ticks_msec()
		_pct = percent(got, total)
		_roll.play()
	var t := (Time.get_ticks_msec() - _t0) / 1000.0
	var ct := _count_time()
	# the count: an ease-out, so it races at first and creeps in at the end
	var k := clampf(t / ct, 0.0, 1.0)
	var shown := roundi(_pct * (1.0 - pow(1.0 - k, 3.0)))
	# the swell and slam, half a beat after the count lands
	var u := t - ct - _half_beat()
	var sc := Vector2.ONE
	var off := Vector2.ZERO
	if u >= 0.0:
		if u < RISE:                                    # swelling up toward you
			var e := 1.0 - pow(1.0 - u / RISE, 2.0)
			sc = Vector2.ONE * lerpf(1.0, BIG, e)
		elif u < RISE + SLAM:                           # slamming back down, accelerating
			var e := pow((u - RISE) / SLAM, 2.0)
			sc = Vector2.ONE * lerpf(BIG, 1.0, e)
		elif u < RISE + SLAM + SETTLE:                  # impact: squash, wobble, shake
			var d := 1.0 - (u - RISE - SLAM) / SETTLE
			var wob := sin((u - RISE - SLAM) * 40.0) * d * d
			sc = Vector2(1.0 + 0.16 * wob, 1.0 - 0.16 * wob)
			off = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 9.0 * d * d
	var text := "%d%%" % shown
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	ci.draw_set_transform(center + off, 0.0, sc)
	var at := Vector2(-w / 2.0, FONT_SIZE * 0.35)   # baseline so the digits sit centred
	ci.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 10, Color(0.1, 0.06, 0.05))
	ci.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, pct_color(shown / 100.0))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Stand-in drum roll: fast snare hits (noise bursts) getting louder.
static func _synth_roll(dur: float) -> AudioStreamWAV:
	var rate := 44100
	var n := int(dur * rate)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var hit_every := rate / 26          # 26 hits a second
	var lp := 0.0
	for i in n:
		var k := float(i) / n
		var since := float(i % hit_every) / rate
		var env := exp(-since * 55.0) * lerpf(0.35, 1.0, k)
		var x := rng.randf_range(-1.0, 1.0)
		lp += (x - lp) * 0.5
		var v := clampf((x - lp * 0.6) * env * 0.8, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(v * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = bytes
	return w
