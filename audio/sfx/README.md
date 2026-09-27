# Sound effects

Drop audio files here with these names and the game picks them up automatically
(any missing one just stays silent). Or assign them on the **CoconutGame** node in
the Inspector (the `Sound` group) — an assigned slot wins over the file. After
adding/replacing a file, click into the Godot editor once so it imports.

| File (any of `.wav` / `.ogg` / `.mp3`) | When it plays |
|----------------------------------------|---------------|
| `cue.<ext>`    | when a fruit leaves the tree — **one beat before** you need to catch it |
| `catch.<ext>`  | you catch a **coconut** (Perfect or Good) |
| `banana.<ext>` | you catch a **banana** (Perfect or Good) |

- Subfolders are fine (`audio/sfx/whatever/catch.wav`), and doubled extensions
  (`catch.wav.wav`) are tolerated — matched by the name before the extension.
- **WAV** imports sample-accurate; **OGG** is smaller. Either is fine for SFX.
- Keep them short and pre-trimmed (no leading silence) so they land on the beat.
- `sfx_volume_db` on the CoconutGame node adjusts the level of all three.

There's a pool of 6 players, so overlapping sounds (a `cue` firing while a
`catch` still rings) don't cut each other off.
