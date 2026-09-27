class_name Beatmap
extends Resource
## The chart for one level, authored in BEATS (not seconds) so it stays locked to
## the music as long as the BPM is unchanged.
##
## Two ways to define cues:
##   1. Fill `cues` explicitly: [{ "beat": 12.0, "cue": "catch" }, ...]
##   2. Leave `cues` empty and describe a repeating phrase with the pattern
##      fields below. `compiled()` expands it.
##
## A compiled cue is a Dictionary: { "beat": float, "cue": String,
## "length": float, "time": float (absolute seconds into the WAV) }.

@export var song_title: String = ""
## Copied onto the Conductor at load by rhythm.gd.
@export var bpm: float = 128.0
@export var first_beat_offset: float = 0.0
## Display-lag compensation for this build/machine (visuals only). Really a user
## setting; lives here until there's an options menu. See Conductor.video_offset.
@export var video_offset: float = 0.0
## This player's input latency (grading + the chart recorder). Also really a user
## setting. See Conductor.input_offset.
@export var input_offset: float = 0.0

@export var cues: Array = []

## Any cue this close (in beats) to a neighbour is the "quick back-to-back" kind
## and gets retagged "banana" by compiled(). 0 disables. Explicit non-"catch"
## cue types in `cues` are left alone. 1.25 = catches 1-beat pairs, ignores 1.5+.
@export var banana_gap: float = 1.25

@export_group("Generated pattern", "pattern_")
## Cue offsets within one phrase, in beats. e.g. son clave 3-2 over 2 bars:
## [0.0, 1.5, 3.0, 5.0, 6.0]
@export var pattern_phrase_beats: Array = []
@export var pattern_phrase_length: float = 8.0   ## beats per phrase
@export var pattern_start_beat: float = 16.0     ## first phrase begins here
@export var pattern_phrase_count: int = 8
@export var pattern_rest_phrases: Array = []     ## 0-based phrase indices left silent
@export var pattern_cue: String = "catch"


## Cues sorted by beat, each with "length" and absolute "time" (seconds into the
## WAV) filled in. Call once at level start; pass the Conductor.
func compiled(conductor: Node) -> Array:
	var raw: Array = cues if not cues.is_empty() else _expand_pattern()
	var out: Array = raw.duplicate(true)
	out.sort_custom(func(a, b): return float(a.get("beat", 0.0)) < float(b.get("beat", 0.0)))
	for c in out:
		c["beat"] = float(c.get("beat", 0.0))
		c["length"] = float(c.get("length", 0.0))
		c["cue"] = String(c.get("cue", pattern_cue))
		c["time"] = conductor.time_of_beat(c["beat"])

	if banana_gap > 0.0:
		for i in out.size():
			if out[i]["cue"] != "catch":
				continue
			var tight := false
			if i > 0 and out[i]["beat"] - out[i - 1]["beat"] <= banana_gap:
				tight = true
			if i < out.size() - 1 and out[i + 1]["beat"] - out[i]["beat"] <= banana_gap:
				tight = true
			if tight:
				out[i]["cue"] = "banana"

	return out


func _expand_pattern() -> Array:
	var list: Array = []
	if pattern_phrase_beats.is_empty():
		return list
	for p in pattern_phrase_count:
		if _is_rest(p):
			continue
		for off in pattern_phrase_beats:
			list.append({
				"beat": pattern_start_beat + p * pattern_phrase_length + float(off),
				"cue": pattern_cue,
			})
	return list


func _is_rest(phrase_index: int) -> bool:
	for r in pattern_rest_phrases:
		if int(r) == phrase_index:
			return true
	return false
