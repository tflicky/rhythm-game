# Devlog

How this game came together, pieced together from the files, the git history
(Sept 27–28, 2026) and the uncommitted work since (Nov 9–11, 2026). For how
the code works today, see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## The core: an audio-clock rhythm engine (early–late Sept)

The first pieces were the chart format and the clock:

- **`Beatmap`** (`scripts/beatmap.gd`, Sept 1) – charts are written in *beats*,
  not seconds, either as an explicit cue list or a repeating pattern phrase.
  Re-rendering the song at the same BPM never breaks a chart.
- **`Conductor`** autoload (`scripts/conductor.gd`) – the single source of
  time. Reads the song position from the audio hardware every frame
  (`get_playback_position` + time since last mix − output latency), converts
  it to beats, and grades presses with `timing_error()`. No `Timer`s and no
  `delta` accumulation anywhere: every cue, animation and hit window is
  derived from this clock.
- **Chart recorder** (`scripts/chart_recorder.gd`) – press F2 in a level and
  tap a chart in by ear, with optional quantize, then save it into the `.tres`.
- **Debug overlay** (`scripts/rhythm_debug.gd`) – editor-only keys for nudging
  the beat, calibration, video and input offsets live.

## Monkey Business (Sept 1 → Sept 27)

The first minigame (`Rhythm.tscn`, `scripts/coconut_game.gd`), on a 128 BPM
bossa nova track. A "twister" monkey hip-bumps the palm, a cue sound plays,
and one beat later you catch the falling coconut. Perfect catches, bobbles,
head bonks and empty-press claps are all shown on the monkey. Bananas are
back-to-back cues retagged automatically and warned with a tap-tap. A
practice round over a metronome comes before the song.

The art went through a few rounds: early sketches, `monkey_swing` and an older
`monkey_twist` pose were dropped in a cleanup commit in favour of the
two-frame `monkey_twist_0/1` bump. Art and sounds are found by file name, with
drawn placeholder shapes until a file exists.

**Since the last commit:** a background **surfer cameo** was added. Mid-song,
a monkey surfing a wave crosses the horizon, bobbing on the beat, over a new
ocean strip with drifting swells and shore foam. The surfing art's soft alpha
edges are rewritten at load time into solid "shape fades" so the ocean
doesn't show through the wave.

## Shipping 1.0.x (Sept 27)

The first commit packed in both levels, a main menu and the docs. That same
evening became a release push:

- **Fixed: art and sounds missing in exported builds.** The folder scan used
  `DirAccess`, which only sees `*.import` stubs in an exported game. It was
  switched to `ResourceLoader.list_directory`.
- **Fixed: catches graded late.** The shipped chart had a 131 ms input offset
  baked in, which put the Perfect window and the fruit's arrival behind the
  beat you hear. It was removed, and the debug keys were locked out of exported
  builds.
- **New: per-computer timing calibration** (`Calibrate.tscn`,
  `scripts/calibrate.gd`, `scripts/settings.gd`). Tap along to a click; the
  median delay is saved to `user://settings.cfg` and replaces the level's
  default input offset. It runs on first launch. The screen then got three quick
  passes in a row: a clearer 1-2-3-4 count-in, shorter text, then simpler text.
- Windows export preset, version bumped to **1.0.2**, and a player-facing
  README with screenshots. The old `RHYTHM_README.md` moved to
  `docs/DEVELOPMENT.md`.

## Grill Master, take 1: call and response with example tongs (Sept 28)

`grill_game.gd` started as an ~90-line stub and became a full level in an
afternoon of commits, on a new 130 BPM `Grill_Song.wav`:

- Chart **generated from the song's stems** (Tongs / Sizzle / Pop): 74 cues,
  each a `call` (the example, not graded) or an `answer` (37 presses).
- Mirrored, **blue-tinted example tongs** (`shaders/tint_grey.gdshader`)
  perform every call; the player copies on the next bar with Space.
- A **practice round** over a metronome teaches the clacks, then the flip.
  Metronome generation was pulled out into the shared `ClickTrack`
  (`scripts/click_track.gd`), now used by both levels and calibration.
- **Reworked: the flip animation is locked to the music clock** (grab on beat
  1, top of the toss on beat 2, land on beat 3) instead of playing at a fixed
  frame rate.
- **Fixed:** practice played the beat-2 scrape on beat 3 too. Beat 3 got a
  real sizzle cut from the stem.
- **Fixed: mismatched patties.** Mirroring the example tongs also mirrored the
  patty, and the original frames had a hole where the tongs covered it. The
  flip was re-exported from Krita as separate back tong / patty / front tong
  layers (`art/grilling/parts/`), so the example draws a whole, un-mirrored
  patty.
- **Fixed: the giant smoke circle.** When the practice click track looped,
  the clock went back to 0, effects got negative ages, and a huge
  inside-out circle was drawn. Effects are now cleared on loop.

## Grill Master, take 2: cues, burgers and a tutorial (Nov 9–11, uncommitted)

The biggest rework in the project: `grill_game.gd` went from ~570 to ~1,800
lines.

- **The example tongs are gone.** The level now uses *cues* instead of a
  mirrored performer. The salt and pepper shakers hop with a shake-shake when
  the patty needs seasoning, and the patty bubbles with a ding-ding when it's
  ready to flip (gold double-ding for the pop). The `ExampleTongs` node and its
  shader material were removed from `Grill.tscn`.
- **Moves now build a burger.** A clack pair knocks the salt shaker, then the
  pepper shaker, and a pinch arcs onto the patty (a miss spills it on the
  floor). The patty starts raw and browns with each landed flip
  (`shaders/patty_cook.gdshader`). A pop drops the patty on the bun, the top
  bun goes on, and the burger hops onto the picnic table. **Three burgers per
  song**, which is why two mid-song flip bars in `beatmaps/grill.tres` were
  changed to `pop` bars. The ending is a close-up of all three burgers with the
  results.
- **Reworked: flips are a hold.** Press on beat 1 to grab, release on beat 2
  to toss, and beat 3 lands by itself. A bad grab or release drops the patty
  with a smoky puff.
- **Reworked: the practice round is a tutorial.** Explainer cards (welcome →
  clack → flip → ready) sit between practice rounds, and a rhythm strip marks
  each press as hit, missed or extra. This replaced the LISTEN / YOUR TURN
  labels.
- **Sound slots.** Every grill sound is now a named slot in
  `audio/sfx/grill/`, with synthesized placeholders (whoosh, sear, ding,
  shaker) until a file exists. The new README there notes that the old
  `sizzle.wav` swells in over about half a second, which is why it sounded
  late as a landing sound.
- **Art slots.** An `ART` table lists every hand-drawn piece (burger layers,
  shakers, table), and a labelled placeholder box stands in until each file
  exists. `scripts/grill_field.gd` draws a placeholder grass field in code
  (`@tool`, so it shows in the editor).
- **One-Burger Test** (`GrillTest.tscn`, `scripts/grill_one_burger.gd`): a
  stripped-down loop (sizzle, sizzle… pop, flip) to answer one question: is
  flipping a single burger on the beat fun by itself?

## Wizard Tower prototype (Nov 9, uncommitted)

A third minigame (`Wizard.tscn`, `scripts/wizard_game.gd`), added to the menu.
An enemy tower lobs a bar of fire and ice balls into the sky. They hang in
lanes like notes, then swoop at you one bar later in the same rhythm. You
counter each one with the opposite element (A = ice, D = fire). Spell bursts
are synthesized per element with a reverb tail. For now it reuses the Monkey
Business song.

Supporting tools were written for it:

- `tools/kra_export.ps1` exports every animated layer of a Krita `.kra` file
  straight to PNG frames (decoding Krita's LZF tiles and applying HSV filter
  masks), and records each layer's canvas position in `frames.json`, so the
  gnome, wand, spell and burst line up exactly as drawn.
- `tools/make_wizard_icon.ps1` builds the menu icon from those frames.

## Other tools

- `tools/tap_composer.html` – a standalone browser page for tapping drums and
  notes over a loop on the keyboard and exporting a `.mid` for BandLab. It's
  for making the music, outside the game itself.

## Loose ends spotted

- `shaders/tint_grey.gdshader` is no longer used by any scene since the example
  tongs were removed. `audio/sfx/grill/scrape.wav` is unused too (the sound
  README already notes this).
- Backup and leftover files: `art/grilling/scene/table.png.bak`,
  `art/monkey/monkey_twist.png~`, `art/grilling/krita animation.kra~`.
- The README's minigame list, controls and project layout don't mention
  Wizard Tower, the One-Burger Test or the grill rework yet. The flip is also
  now a hold rather than a press.
- Everything from November is uncommitted.
