# Wizard sounds

Drop your recordings in this folder with these names (`.wav`, `.ogg` or `.mp3`) and
the Wizard level uses them instead of the synth stand-ins. Any file that's missing
keeps its stand-in, so you can replace them one at a time. After adding a file,
click into the Godot editor once so it imports.

| File | When it plays |
|------|---------------|
| `launch_fire` | a **fireball** shoots up from the enemy tower (part of the call) |
| `launch_ice`  | an **iceball** shoots up from the enemy tower (part of the call) |
| `cast_fire`   | you cast a **fire** spell |
| `cast_ice`    | you cast an **ice** spell (also plays once when the level opens) |
| `burst_fire`  | your fire spell smashes an iceball. It can ring out, up to ~1.5 s |
| `burst_ice`   | your ice spell smashes a fireball. It can ring out, up to ~1.5 s |
| `hurt`        | a ball gets through and hits you |

Tips:
- Make the two launches easy to tell apart by ear (low vs high works well), since
  the player hears the call before seeing the balls up close.
- Use WAV, trimmed so the hit starts at the very beginning of the file.
- Record fairly loud. The level plays the ice sounds a little quieter than fire,
  so if one sits too low or high, tell Claude and the volume can be adjusted.
