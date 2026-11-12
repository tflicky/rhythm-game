# Grill sound effects

Every sound in the grill game is a file in this folder, named after its **slot**.
Drop in `<slot>.wav` (or `.ogg` / `.mp3`) and the game uses it. Then click into the
Godot editor once so it imports. Any slot without a file plays a built-in
placeholder (a synthesized bell, rattle or noise), and the game prints which
slots still use one when the level starts.

To replace a sound that already has a file here, overwrite the file with yours,
keeping the same name.

## Grill Master (`Grill.tscn`)

| Slot | When it plays | Now |
|------|---------------|-----|
| `salt_cue`   | cue: the salt shaker hops ("season me", first clack) | placeholder rattle |
| `pepper_cue` | cue: the pepper shaker hops (second clack) | placeholder rattle |
| `flip_cue_1` | cue: patty bubbles on beat 1 of a flip bar | placeholder bell |
| `flip_cue_2` | cue: patty bubbles on beat 2 of a flip bar | placeholder bell |
| `pop_cue`    | cue: beats 1 and 2 of a pop bar (the flip onto the bun) | placeholder bell |
| `salt_shake` | your salt shake (first press of a seasoning pair) | placeholder rattle |
| `pepper_shake` | your pepper shake (second press) | placeholder rattle |
| `tong`       | a press when there's nothing to answer (the tongs just click) | `tong.wav` |
| `flip`       | your grab on beat 1 (press) | `flip.wav` |
| `whoosh`     | your toss on beat 2 (let go) | placeholder noise |
| `land`       | the patty lands on beat 3 | placeholder noise |
| `sizzle`     | quiet tail under `land` on a normal flip | `sizzle.wav` |
| `pop`        | the patty lands on the bun (beat 3 of a pop) | `pop.wav` |

## One-Burger Test (`GrillTest.tscn`)

| Slot | When it plays | Now |
|------|---------------|-----|
| `cook_sizzle` | every beat while the patty cooks ("get ready") | placeholder hiss |
| `pop`         | the flip beat ("flip now") -- shared with Grill Master | `pop.wav` |
| `tong`        | presses that aren't a flip -- shared with Grill Master | `tong.wav` |

## Making them land on the beat

The game starts each sound exactly on its beat, so **the moment you want heard on
the beat has to be the very first thing in the file**:

- **No silence at the start.** Trim right up to the attack.
- **Hit hard at the start.** The loud part should come within the first ~10 ms. A
  sound that fades or swells in is heard late even when it's started on time.
  The old `sizzle.wav` builds up for about half a second, which is why it felt
  late as a landing sound.
- **Keep cues short**, ideally under ~0.3 s, so back-to-back beats don't blur.
- **WAV** imports sample-accurately and is the safest choice; OGG is fine too.
- **Loudness:** match your files to each other. The game turns some down a bit
  (e.g. `sizzle` is played quiet as a tail), and levels can be fine-tuned in
  `_cue_sound()` / `_sound()` in `scripts/grill_game.gd`.

The practice-round metronome click is shared with the other levels
(`scripts/click_track.gd`) and isn't a grill slot.
