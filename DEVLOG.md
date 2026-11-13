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

## Grill Master, take 2: cues, burgers and a tutorial (Nov 9–11)

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

## Wizard Tower prototype (Nov 9)

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

## Boomerang prototype (Nov 12)

A new level (`Boomerang.tscn`, `scripts/boomerang_game.gd`, 4th on the menu),
from the idea: throw a boomerang with Space and catch it with Space, with three
counts to catch on: "1 2 3 4 catch", "1 & 2 & 3 & catch" and "1 2 3 catch".

What it is now:

- **Cue, cue, THROW.** On the two beats before each throw, the thrower makes a
  cue noise. Each boomerang colour has its own noise (red "hah" = 1 2 3, green
  "hee" = 1 & 2 & 3 &, blue "hoo" = 1 2 3 4), so you know the count by ear
  before you throw. The count then plays while it flies, and you catch right
  after it.
- **Timing:** one throw every 2 bars, always on a downbeat. Red and green
  catch 4 beats later, blue 5. The colours mix after the first two, and the
  count board at the top only shows the first time you meet each colour.
- **Balloons:** a clean throw sends balloons into the boomerang's path, and it
  pops them on a count (pop on the beat, +20). A fumbled throw gets none.
- **Misses:** a missed throw fumbles it out anyway. A missed catch bonks the
  thrower on the head.
- All art and sound are placeholders. Real sounds dropped into
  `audio/sfx/boomerang/` (`cue_three`, `cue_and`, `cue_four`, `count_1`…, `pop`,
  …) are used automatically, and the song is still the monkey track until the
  custom one is made.

How it got there (it took a few rounds):

1. The first version was built entirely from the one-line idea. It worked,
   but: *"I really like the boomerang game but it feels like I didnt make it."*
   From now on, design choices get asked about rather than invented.
2. *"There should always be a call before the players response."* First try:
   the whole rhythm played as sound, then you repeat it. Rejected: *"the call
   should be an audio cue I mean, the example character isnt as fun"* and
   *"that's not the most fun"*. The model was a classic rhythm-game warm-up
   where *"the monkey makes a noise twice then throws the ball all in beat"*.
   That became "cue, cue, THROW", with a different noise for each colour.
3. *"Its a little too easy"*, plus *"I like the idea of the player popping
   balloons floating by"*. The throws were packed closer (3 beats after each
   catch), the colours mixed early, the count board hidden, and balloons added.
4. *"I think its a little too hard now I want it to be more like the original
   timings we had and more on the beat"*. Back to every 2 bars on the
   downbeat. And *"I prefer only the balloons that will be popped to be
   present on screen"*: balloons now only appear after a clean throw.

The main menu was getting too tall with four levels (the title and Calibrate
button were cut off), so the rows got tighter and the icons smaller
(`ICON_SCALE`).

## Other tools

- `tools/tap_composer.html` – a standalone browser page for tapping drums and
  notes over a loop on the keyboard and exporting a `.mid` for BandLab. It's
  for making the music, outside the game itself.

## Loose ends spotted

- Boomerang has no menu icon yet, and its "1 & 2 & 3 &" and "1 2 3" counts
  catch on the same beat (only the cue noise and the hops tell them apart).
- `docs/DEVELOPMENT.md` hasn't been checked against the November changes.

## Housekeeping (Nov 12)

Removed leftovers nothing used: `shaders/tint_grey.gdshader` (only the old
example tongs used it), `audio/sfx/grill/scrape.wav`, and the backup files
`table.png.bak`, `monkey_twist.png~` and `krita animation.kra~`. The README now
covers the grill rework, Wizard Tower, the One-Burger Test and Boomerang, with a
fresh menu screenshot.

## Grill Master: your own sounds and backdrop (Nov 12)

The goal for the day, in my words: *"The goal is to use as little of your sound
effects as possible and try to use what I can create."* Every grill sound and the
new backdrop pieces now come from my own recordings and drawings.

**Sounds**

- **Flip cue:** the two bell dings became *"a small sizzle and then a big
  sizzle. Then that's your cue to flip."* Both are cut from my `sizzle.wav`
  (`flip_cue_1.wav` / `flip_cue_2.wav`), started right on the loud part so they
  land on the beat. Tutorial cards now say "Small sizzle, BIG sizzle?".
- **Salt & pepper call:** made different from the shake you answer with. It's my
  `tong.wav`, pitched up for salt and down for pepper.
- **Salt & pepper shakes (your answer):** single strokes from the shaker take I
  recorded for the Barrel Blast tribute video, one pitched up for salt, one down
  for pepper.
- **Pop call (onto the bun):** my own "Pop sound" recording replaced the gold
  double ding. It was recorded very quietly with half a second of silence in
  front, so it got trimmed to the pop and turned up.
- **Bug:** the first sizzle cut was *"very staticky and loud compared to the
  others and it cuts off very unnaturally."* I had boosted it ~13 dB through a
  limiter, which pumped up the hiss, and gave it a short fade. Fixed by dropping
  the boost, filtering out the harsh top end (and the rumble), setting levels
  under the other sounds, and giving both a long, smooth fade-out.

Only the whoosh (let go) and the landing thump are still placeholder sounds.

**Layout and backdrop**

- Grill (with tongs and patty) moved 100 px right; the picnic table is 20%
  bigger and moved right, with the shakers, served-burger spots and ground
  shadows moved to match. The score text got a light outline since the grill lid
  now sits behind it.
- Drew my own **grass tuft, bush and football** in `krita animation.kra`, exported
  to `art/grilling/scene/`. The grass replaces the code-drawn tufts, spread
  evenly after *"there are too many grass sprites concentrated towards the
  front."* The bush sits where I drew it, and small copies of it now make up the
  hazy line along the horizon.
- **Football cameo:** like the surfing monkey, a football gets thrown once across
  the sky behind everything, beats 80–88 (a stretch with no cues), nose following
  the arc with a little spiral wobble. Song only, not practice.

## No more points, a calmer tutorial, and grill polish (Nov 13)

**Scoring, every level.** *"I don't really want there to be points or anything. I
just want it to tell you how many you got out of how many there were and tell the
player the percent."* SCORE and COMBO are gone from all four levels (and the banana /
balloon bonuses with them). Every results screen now says "You got X / Y" with a big
percent coloured red at 0%, reddish yellow at 50%, green at 100%, blending in
between. One shared file, `scripts/results.gd`, draws it for every level.

**Grill Master tutorial.** This took a few rounds:
- First: a count-in bar (4, 3, 2, 1 over the tongs) between the example and your
  try, because going straight from the example into "your turn" was abrupt and
  players had to rewatch it. It drops after your first clean try so you finish at
  song speed.
- Then *"clunky and cluttered"*: 4 cards became 2, and messages only show when a try fails.
- Then *"I want to do it how Rhythm Heaven does their tutorials... I dislike all the
  text. I want it to be simple and easy to understand."* Big text boxes became a
  slim caption bar, and the strip, labels and side panel came out.
- Then *"the 1 & 2 & thing at the top was the best option we had"*, so the rhythm
  strip came back, with short titles (Listen / Get ready / Your turn!). The fix I
  actually wanted: *"some build up to where it teaches you the hold thing because it
  happens at beat one... the progress bar to start a little earlier."* The strip now
  shows a faded "4 &" of the bar before and switches a beat early, so you watch the
  playhead come into the HOLD on beat 1.

**Grill polish**
- The tongs draw on top of everything (shakers, steam, plate), and they moved right
  so they don't block the salt and pepper. They also have a dark outline now; they
  were hard to see as light grey on light grass and the tan table.
- Pressing SPACE with nothing to answer makes the tongs clap together.
- Table and bench shadows: the soft ovals *"don't feel realistic"*, so each shadow is
  now the shape of the tabletop / bench seat dropped straight down under it.
- The big bush is gone; my bush is only the horizon line now, on a solid dark-green
  band so no sky shows through the gaps.
- Bug: the outline shader first failed to compile (Godot doesn't allow `return` in a
  canvas shader's fragment()), which also killed the raw-patty colouring until fixed.

**Menu icons:** Monkey Business is just the banana now; Wizard is just the gnome
(the icon script got reframed so the gnome fills it). Got there after a couple of
tries: fireball only, then gnome + fireball, then gnome only.

## Results that count up, a pause menu, and Boomerang becomes Juggling (Nov 13, later)

**Bug: the grill said 0%.** *"it says i got 0% for the burger one when i def didnt
26/0"*. The grill counted its total presses from the list of presses still waiting,
but by the end of the song that list is empty (every press gets taken off it as you
play), so it divided by zero. Now the total is counted when the song starts.

**Results are just the percent, and it performs.** *"the only stats that should be
there should be the percent sign for all of the games, and it should start from 0
and like count up incremently pretty fast then near the end it slows down then when
its done counting it waits a half beat then the number moves towards the player and
slams back down"*. Every level now counts 0 → your percent (fast, then easing in,
colour going red → green as it climbs) over a drum roll, then half a beat later it
swells toward you and slams down with a squash and a shake. The drum roll is a slot
for my own recording (`audio/sfx/drum_roll.wav`); a synth roll stands in for now.

**Pause menu.** *"when you click escape in the level it shouldnt automatically boot
you out, it should bring up a menu that asks if you want to continue, retry, or
quit, then count in for when you press continue"*. Esc now freezes the level and
the music: Continue / Retry / Quit. Continue counts 3, 2, 1 lined up with exactly
where the music stopped, so the song comes back right on the beat (tested: within
5 ms). Esc on the results screen still goes straight to the menu.

**Boomerang is gone; Juggling replaces it.** *"starts out juggling tennis balls in a
backyard then pauses a third of the way through then the character is doing it on a
unicycle with bowling pins, then for the last segment hes doing it on a trapeeze over
a shark tank"*, and for the last act, *"I want it to be flaming swords"*.
My design calls:
- *"one click for both, one hand is catching and the other is throwing so it should
  be a game where you are holding a beat throughout the song"*, with the rhythm
  *"slightly faster or just changes the beat slightly"* each act.
- The call is *"when the beat starts for the first time, then a call for when it
  stops"*: the juggler shows each act's rhythm for a bar ("hup" per catch), and a
  whistle on the last bar's downbeat says finish this bar and stop.
- A curtain closes and opens between acts. Rhythms to start: 1 2 3 4 / 1 2 3 & 4 /
  1 2 & 3 4 &.
- Placeholder art and the monkey song for now; my own song and drawings come next.

## A menu icon for Juggling (Nov 13, later still)

*"make a menu icon for the juggling level"*. Juggling was the only level with an
empty icon slot. It now shows one prop for each act (a flaming sword, a bowling pin
and a tennis ball) on a dotted juggling arc. No juggling art exists yet, so the icon
is drawn in code by `tools/make_juggle_icon.gd`, which renders it to
`art/juggling/icon.png`. Saving my own drawing over that PNG replaces it.

## The Wizard gets its own song (Nov 13, later still)

*"here is the wizard song"*: `Wizard_2.wav`, now `audio/music/Wizard_Song.wav`,
110 BPM with beat 1 right at the start of the file. Measuring the tempo from the
audio didn't work: the intro has no steady beat, and guesses ran anywhere from
128 to 133, so I just gave it the BPM (110). At 110 the song is about 25 bars, room
for 11 of the 17 call patterns. The level now picks an even spread of them so it
still builds to the hardest ones, and uses more if the song gets longer. A bot hit
all 40 balls Perfect, and in play it *"feels on beat"*.
