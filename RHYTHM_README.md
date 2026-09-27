# Rhythm Game — timing scaffold

Rhythm Heaven–style level built on a single principle: **every beat, cue,
animation and hit window is derived from the audio playback clock**, never from
`Timer` nodes or `_process(delta)` accumulation. That is the only way sync stays
exact over a 50+ second song.

## Files

| File | Role |
|------|------|
| `scripts/conductor.gd` | Autoload `Conductor`. The clock. Reads song position from the audio hardware every frame, converts to beats, emits `beat` / `half_beat` / `measure`. Grading helpers: `timing_error()` (input-latency compensated), `timing_error_raw()`, `time_of_beat()`, `nearest_beat()`. |
| `scripts/beatmap.gd` | `Beatmap` resource. The chart, authored in **beats** — either an explicit `cues` list or a repeating `pattern_*` phrase. `compiled()` expands + sorts + fills absolute WAV timestamps. |
| `beatmaps/rhythm_monkey.tres` | The level: son clave 3-2 phrase `[0, 1.5, 3, 5, 6]` every 8 beats, 10 phrases from beat 16, phrase 4 silent. 45 cues. |
| `scripts/coconut_game.gd` | The **Monkey Business** minigame. Palm on the left, monkey centre-bottom. Fruit appears from behind the palm's front leaves and falls to the monkey's hands over exactly 1 beat. Outcome is shown entirely by the monkey: Perfect = clean catch, Good = bobble + fruit drops beside him, Miss = fruit bonks his head. No hit text. A second "twister" monkey leans on the palm trunk in the foreground (legs off the bottom of the screen) and hip-bumps it on every fruit cue sound (`monkey_twist_0/1.png`), rocking the palm (`twist_*`, `palm_shake*` exports). Renders from `art/` textures with placeholder shapes as fallback. |
| `art/` | Drop your PNGs here (see `art/README.md`). Empty slots fall back to the built-in shapes, so art can be added one piece at a time. |
| `audio/sfx/` | Drop `cue` / `catch` / `banana` sound files here (see `audio/sfx/README.md`). Empty = silent. `cue` plays when the fruit leaves the tree (a beat before). `catch`/`banana` is the thunk — by default **pre-scheduled onto the cue's beat** (`sfx_catch_on_beat`), for every fruit, so it locks to the music; the monkey shows catch/bobble/miss. Flip `sfx_catch_on_beat` off for a reactive thunk that only fires on a clean Perfect (tight to your input but ~1 frame + audio latency after the beat). |
| `scripts/rhythm.gd` | Root of `Rhythm.tscn`. Wires Conductor ↔ AudioStreamPlayer, loads the beatmap, feeds cues to the game. `R` restarts. |
| `scripts/rhythm_debug.gd` | Calibration overlay (top-left). Live readout + tap meter (`T`) + input calibration (`C`). Metronome off by default (`M`). Delete once timing is locked. |

## Playing

Run `Rhythm.tscn` (F5). It opens with a **practice round**: a coconut every 4 beats over a metronome click (not the song), "YOU" over the catcher and a listen-for-the-cue / SPACEBAR hint; **S** skips it; 3 clean (Perfect) catches → "Nice! Here we go!" → the real chart from the top. Tune or switch it off in the `Practice round` exports on the root node; `R` after passing replays without practice. **Space / click / tap** as the fruit reaches the monkey's
hands — right on the beat. `R` restarts.

- Perfect (±75 ms) → monkey catches it clean.
- Good (±150 ms) → monkey bobbles it; fruit bumps off his hands and drops past his
  feet off the bottom (target `monkey_pos + deflect_offset`, y forced below screen).
- Press with nothing to catch (no fruit falling, or outside the Good window) → monkey claps (`monkey_clap.png`, ~0.25 s); the fruit keeps falling.
- Before the first fruit of the song (not practice) a "3, 2, 1, GO!" count-in ticks on the 4 beats before its cue sound (`count_in` export). The cue sound is boosted by `sfx_cue_db` (+4 dB) through a limited "SFX" bus so it cuts through the music without clipping.
- Past the Good window → Miss: fruit bonks his head (recoil + stars), does a small
  arc off the head toward the COMBO readout (`HUD_LEFT`), then keeps falling off
  the bottom of the screen.
- The fruit reaches his hands the moment a perfectly-timed press *registers*
  (cue beat shifted by `Conductor.input_offset`), so what you see and when you
  click line up. `_fall_pos(u)` is one unbroken curve — leaves the tree, hits the
  hands at u=1, keeps accelerating down past the head and off screen. No stall.
- Timing consts at the top of `coconut_game.gd` (`LEAD_BEATS`, `PERFECT`,
  `GOOD`, `MISS_TAIL`). Layout / art in the `@export`s — see `art/README.md`.

## Recording the chart by ear (record mode)

Instead of computing cue beats, tap them against the song:

1. Run `Rhythm.tscn`, press **F2** to enter record mode (song restarts).
2. **Space / click** on every beat you want a coconut. Taps are input-latency
   compensated (`Conductor.input_offset`).
3. **Q** cycles quantize — leave it **OFF** to keep exactly what you tapped, or
   snap to `1/4` / `1/8` / `1/16` / `1/2` beat for a tidy chart.
4. **Z** undo last · **X** clear all · **R** restart (marks kept).
5. **S** saves the marks into `rhythm_monkey.tres` as `cues` (also prints the
   array to the console as a backup).
6. **F2** back to play mode, **R** to restart — the coconut game now runs your
   chart (`cues` non-empty overrides the generated pattern).

To go back to the generated pattern, empty `cues` in the `.tres` again.

## Editing the chart by hand

`beatmaps/rhythm_monkey.tres`, pattern fields (used only while `cues` is empty):

| Field | Meaning |
|-------|---------|
| `pattern_phrase_beats` | Cue offsets within one phrase, in beats. `[0, 1.5, 3, 5, 6]` = son clave 3-2. |
| `pattern_phrase_length` | Beats per phrase (8 = two 4/4 bars). |
| `pattern_start_beat` | Beat the first phrase begins (16 = after a 4-bar intro). |
| `pattern_phrase_count` | How many phrases. |
| `pattern_rest_phrases` | 0-based phrase indices left silent (breathers). |

Or set `cues` explicitly (`[{ "beat": 12.0, "cue": "catch" }, ...]`) and the
pattern is ignored. Minimum gap between cues should stay ≥ `LEAD_BEATS` (1.0)
so every coconut gets its full fall — the son clave 3-2 min gap is exactly 1.0.

### Bananas

`compiled()` retags any cue within `banana_gap` beats (default **1.25**) of a
neighbour as `"banana"` — the quick back-to-back hits. Bananas render as a yellow
crescent with a yellow target ring, the monkey does a chomp pop when it catches
one, and they're worth +20. Same catch timing as a coconut. Set `banana_gap = 0`
to turn the feature off; raise it to catch looser clusters.

## The Conductor formula

```gdscript
song_position = player.get_playback_position()
              + AudioServer.get_time_since_last_mix()   # sub-buffer precision
              - AudioServer.get_output_latency()        # what you actually hear
              - calibration_offset                      # manual trim
song_position_in_beats = (song_position - first_beat_offset) / (60.0 / bpm)
```

## Calibration (do this before any gameplay tuning)

1. Run `Rhythm.tscn` (F5). The overlay shows in the top-left and you hear a click
   on every beat — accented on bar downbeats.
2. Listen to the click against the music.
   - **Click drifts further off as the song goes on** → BPM is wrong. Fix the
     `bpm` in `rhythm_monkey.tres` (and it must match what you built in BandLab).
   - **Click is a constant amount early/late the whole time** → offset is wrong.
     Nudge with the keys below until it sits dead on the groove.
3. Keys (overlay is the source of truth):
   - `Up` / `Down` — `first_beat_offset` ±5 ms (moves the whole grid vs the audio)
   - `]` / `[` — `calibration_offset` ±5 ms (audio output latency trim)
   - `.` / `,` — `video_offset` ±5 ms (display lag: draw visuals earlier / later)
   - `T` — tap; prints raw + compensated error vs the nearest beat
   - `C` — set `input_offset` to the median of your recent taps
   - `M` — mute/unmute metronome · `R` — restart level
4. When it's locked, copy the final `first_beat_offset` into `rhythm_monkey.tres`.

`first_beat_offset` = seconds into the WAV where bar 1 beat 1 lands. Best first
estimate: open `audio/music/Rhythm_Monkey.wav` in an audio editor, zoom on the
start, read the timestamp of the first downbeat transient. For Rhythm_Monkey it
is **0.0** — the track starts on the downbeat with no lead-in.

### Four offsets — keep them separate

| Value | Fixes | Affects | How to tune |
|-------|-------|---------|-------------|
| `first_beat_offset` | Where beat 1 sits in the WAV — the beat grid vs the music. | audio clock → everything | Metronome drifts across the song → wrong BPM. Constant gap → `Up`/`Down`. |
| `calibration_offset` | Audio output latency the OS under-reports. | audio clock → everything | `]`/`[` until a tap timed to the *sound* reads ~0. |
| `video_offset` | Display lag — frames you see trail the sound. Visuals are drawn this far **ahead** so they land on screen with the beat. | **drawing only** | `.` to draw earlier / `,` later, until the fruit *looks* like it reaches the monkey's hands exactly when you hear the beat. |
| `input_offset` | *This player's* taps landing late (keyboard + reaction + OS queue). | **input grading only** | Tap `T` to the beat ~12×, press `C`. Tight cluster ~+80–130 ms = normal; `C` cancels it. |

Calibration order: **first_beat_offset / calibration_offset** (audio in sync) →
**video_offset** (coconut looks on-beat) → **input_offset** (`T`+`C`, catches feel
fair). Never fix a video or input problem with `first_beat_offset` — that shoves
the music itself off the grid.

`video_offset` and `input_offset` are really per-machine user settings; they live
on the Beatmap / are set at runtime for now, until there's an options menu.

## Building the real chart

Edit `beatmaps/rhythm_monkey.tres`. Each cue:

```
{ "beat": 12.0, "cue": "tap" }
{ "beat": 16.0, "cue": "hold", "length": 2.0 }
```

`beat` is counted from the first downbeat (beat 0). Because cues are in beats,
re-rendering the song at the same BPM never breaks the chart.

## Wiring a minigame

```gdscript
func _ready() -> void:
    Conductor.beat.connect(_on_beat)

func _on_beat(i: int) -> void:
    # spawn the telegraph for a cue a couple beats ahead, so the visual
    # windup lands the player's input right on cue["time"].

func _unhandled_input(e: InputEvent) -> void:
    if e.is_action_pressed("hit"):
        var err := Conductor.timing_error(target_cue_beat)  # seconds, signed
        if absf(err) <= 0.045:   grade = "Perfect"
        elif absf(err) <= 0.09:  grade = "OK"
        else:                    grade = "Miss"
```

Grade against `Conductor.timing_error(...)` — measured from the audio clock —
never against when the input callback happened to fire.

## Notes

- `Rhythm_Monkey.wav` import is set to **PCM** (`compress/mode=0`), not QOA — a
  rhythm game wants sample-accurate, uncompressed audio. Keep it that way.
- Track: 44.1 kHz / 16-bit stereo, ~52.6 s, exported via ffmpeg (no MP3 padding).
