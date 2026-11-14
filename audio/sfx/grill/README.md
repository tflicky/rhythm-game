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
| `flip_cue_2` | the call: each patty landing on the grill, on its beat | `flip_cue_2.wav` = 0.45 s cut of your sizzle.wav |
| `flip`       | your press: the tongs grab and flip a patty | `flip.wav` |
| `sizzle`     | quietly, as the flipped patty lands back on the grill | `sizzle.wav` |
| `tong`       | a press with nothing to flip (the tongs just click) | `tong.wav` |

The other files here (`salt_cue`, `pepper_cue`, `salt_shake`, `pepper_shake`,
`flip_cue_1`, `pop_cue`, `pop`) were for the old two-move version of the game and
aren't used by it any more. `pop` is still used by the One-Burger Test.

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
