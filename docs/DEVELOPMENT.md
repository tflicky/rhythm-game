# Development notes

How the game works under the hood. For playing it, see the [README](../README.md).

The core rule: **every beat, cue, animation and hit window is derived from the
audio playback clock**, never from `Timer` nodes or `_process(delta)`
accumulation. That's the only way sync stays exact over a whole song.

## Files

| File | Role |
|------|------|
| `scripts/conductor.gd` | Autoload `Conductor`: the clock. Reads song position from the audio hardware every frame, converts to beats, emits `beat` / `half_beat` / `measure`. Grading helpers: `timing_error()` (input-latency compensated), `timing_error_raw()`, `time_of_beat()`, `nearest_beat()`. |
| `scripts/beatmap.gd` | `Beatmap` resource: a chart authored in **beats**, either an explicit `cues` list or a repeating `pattern_*` phrase. `compiled()` sorts, tags bananas and fills in absolute song times. |
| `beatmaps/rhythm_monkey.tres` | The Monkey Business chart: 42 recorded cues at 128 BPM. |
| `scripts/rhythm.gd` | Root of `Rhythm.tscn`. Wires Conductor ↔ AudioStreamPlayer, loads the beatmap and this computer's calibration, runs the practice round, then feeds cues to the game. |
| `scripts/coconut_game.gd` | **Monkey Business.** Palm on the left, catcher monkey centre-bottom, "twister" monkey hip-bumping the trunk on every cue sound. Fruit falls from the leaves to the catcher's hands over exactly 1 beat. Feedback is all in the monkey: catch, bobble, bonk, or clap on an empty press. Loads art from `art/` by file name, with drawn placeholder shapes as a fallback. |
| `scripts/calibrate.gd` | Timing calibration screen (`Calibrate.tscn`). Shown on first launch and from the menu. |
| `scripts/settings.gd` | `Settings`: per-computer values saved in `user://settings.cfg` (currently just the calibrated `input_offset`). |
| `scripts/main_menu.gd` | Level select (`MainMenu.tscn`, the main scene). Adding a level is one entry in `LEVELS`. |
| `scripts/grill_game.gd` | **Grill Master** test bed: tongs tap / flip animations over the song. |
| `scripts/chart_recorder.gd` | Record mode: tap a chart in by ear (see below). |
| `scripts/rhythm_debug.gd` | Hidden calibration overlay for development. Its keys only work when running from the editor, never in an exported game. |
| `art/`, `audio/sfx/` | Art and sound slots, see [art/README.md](../art/README.md) and [audio/sfx/README.md](../audio/sfx/README.md). |

## Monkey Business rules

- The cue sound plays **one beat before** each catch, when the fruit leaves the tree.
- **Perfect** (±75 ms) → clean catch. **Good** (±150 ms) → he bobbles it and it drops past his feet.
- Past the Good window → **Miss**: the fruit bonks his head, arcs off toward the COMBO readout, and falls off screen.
- A press with nothing catchable (no fruit falling, or outside the Good window) → he **claps**; the fruit keeps falling.
- The catch thunk is pre-scheduled onto the beat for every fruit (`sfx_catch_on_beat`), so it locks to the music.
- Before the song's first fruit, a **3, 2, 1, GO!** count-in ticks on the 4 beats before its cue (`count_in`).
- The cue sound gets `sfx_cue_db` (+4 dB) through an "SFX" bus with a limiter, so it cuts through the music without clipping.
- Timing constants are at the top of `coconut_game.gd` (`LEAD_BEATS`, `PERFECT`, `GOOD`, `MISS_TAIL`). Layout and art sizing are `@export`s on the **CoconutGame** node.

**Practice round** (`rhythm.gd`, *Practice round* exports): a coconut every 4 beats
over a metronome click instead of the song. 3 clean catches → "Nice! Here we go!" →
the real chart. **S** skips it. Turn `practice` off to go straight to the song while testing.

**Bananas:** `compiled()` retags any cue within `banana_gap` beats (default 1.25) of a
neighbour as `"banana"`, for the quick back-to-back hits. A banana pair warns with a
tap-tap two beats ahead and is worth +20. Set `banana_gap = 0` to turn it off.

## Charting

### Record by ear

1. Run `Rhythm.tscn` and press **F2** for record mode (the song restarts).
2. Press **Space** / click on every beat you want a coconut. Taps are compensated by `Conductor.input_offset`.
3. **Q** cycles quantize: **OFF** keeps exactly what you tapped, or snap to `1/4` / `1/8` / `1/16` / `1/2` beat.
4. **Z** undo last · **X** clear all · **R** restart (marks kept).
5. **S** saves the marks into `rhythm_monkey.tres` as `cues` (also printed to the console as a backup).
6. **F2** back to play mode; the game now runs your chart.

### Edit by hand

Set `cues` in `beatmaps/rhythm_monkey.tres` directly:

```
cues = [{ "beat": 17.0, "cue": "catch" }, { "beat": 21.0, "cue": "catch" }, ...]
```

`beat` counts from the first downbeat (beat 0). Because cues are in beats, re-rendering
the song at the same BPM never breaks the chart. Keep cues at least `LEAD_BEATS` (1.0)
apart so every coconut gets its full fall.

While `cues` is empty, a repeating pattern is generated instead:

| Field | Meaning |
|-------|---------|
| `pattern_phrase_beats` | Cue offsets within one phrase, in beats. `[0, 1.5, 3, 5, 6]` = son clave 3-2. |
| `pattern_phrase_length` | Beats per phrase (8 = two 4/4 bars). |
| `pattern_start_beat` | Beat the first phrase begins. |
| `pattern_phrase_count` | How many phrases. |
| `pattern_rest_phrases` | 0-based phrase indices left silent (breathers). |

## Timing

### The Conductor formula

```gdscript
song_position = player.get_playback_position()
              + AudioServer.get_time_since_last_mix()   # sub-buffer precision
              - AudioServer.get_output_latency()        # what you actually hear
              - calibration_offset                      # manual trim
song_position_in_beats = (song_position - first_beat_offset) / (60.0 / bpm)
```

Grade presses with `Conductor.timing_error(beat)` (audio clock, input-latency
compensated), never by when the input callback happened to fire.

### The four offsets

| Value | Fixes | Affects | Set by |
|-------|-------|---------|--------|
| `first_beat_offset` | Where beat 1 sits in the WAV. | Everything | Beatmap. `0.0` for this song, which starts on the downbeat. |
| `calibration_offset` | Audio output latency the OS under-reports. | Everything | Debug overlay `[` / `]` (development only). |
| `video_offset` | Display lag: visuals are drawn this far ahead. | Drawing only | Beatmap / debug overlay `,` / `.`. |
| `input_offset` | Delay between the player pressing and the game hearing it, plus any audio delay the OS doesn't report. | Grading, and when the fruit reaches the hands | **The calibration screen**, saved per computer. Falls back to the beatmap value (0). |

Never fix a video or input problem with `first_beat_offset`: that shoves the music
itself off the grid.

### Debug overlay (editor only)

`DebugLayer/RhythmDebug` in `Rhythm.tscn` (hidden by default; set it visible to see
the readout). Its keys only work when running from the editor:

- `Up` / `Down`: `first_beat_offset` ±5 ms. If the metronome drifts over the song, the BPM is wrong instead.
- `]` / `[`: `calibration_offset` ±5 ms
- `.` / `,`: `video_offset` ±5 ms
- `T`: tap, printing the raw and compensated error · `C`: set `input_offset` from recent taps (this session only)
- `M`: metronome click on/off

## Wiring a new minigame

```gdscript
func _ready() -> void:
    Conductor.beat.connect(_on_beat)

func _on_beat(i: int) -> void:
    # start the telegraph for a cue a beat or two ahead, so the wind-up
    # lands the player's press right on the cue's beat.
    pass

func _unhandled_input(e: InputEvent) -> void:
    if e.is_action_pressed("ui_accept"):
        var err := Conductor.timing_error(target_beat)  # seconds, -ve early / +ve late
        # compare absf(err) against your Perfect / Good windows
```

Add it to `LEVELS` in `scripts/main_menu.gd` to put it on the menu.

## Building

**Project → Export → Windows Desktop** (preset in `export_presets.cfg`) produces a
single `build/RhythmGame.exe` with the game data embedded. `build/` is git-ignored.
Ship it zipped as a GitHub release.

Files are found by name at runtime with `ResourceLoader.list_directory`, not
`DirAccess`. In an exported game the folders only hold `*.import` stubs, so a plain
directory listing finds nothing there.

## Notes

- `audio/music/Rhythm_Game.wav` imports as **PCM** (`compress/mode=0`), not QOA. A rhythm game wants sample-accurate, uncompressed audio.
- Track: 44.1 kHz / 16-bit stereo, ~71 s, 128 BPM.
