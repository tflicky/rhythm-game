# Artwork

Drop PNGs in this folder with these exact names (or assign them on the
**CoconutGame** node in the Inspector). Every missing file falls back to a
placeholder shape, so you can add art one piece at a time and always have a
runnable game. After adding/replacing a file, click into the Godot editor once so
it imports, then re-run.

## The drawings

### Backdrop

| File | What it is | Size | Background |
|------|------------|------|-----------|
| `background.png` | Sky, horizon, distant scenery — whatever fills the screen behind everything. Stretched to 1152×648. | 1152×648 | **opaque** (only file that is) |
| `ground.png` | *(optional)* foreground ground/beach strip from y≈560 to the bottom. Skip it and paint the ground into `background.png` instead. | ~1152×160 | transparent above the ground line |

### Palm tree — LEFT of screen

Simplest: **`palm_tree.png`** — the whole tree as one image, anchored bottom-centre
at `palm_pos`. The top `palm_crown_frac` (0.55) of the image is treated as the
leaves and redrawn on top, so the fruit **emerges from behind the fronds**
(always drawn behind that band, and in front of the monkeys). Draw the crown in the top ~55%
of the image and put `leaf_spawn` inside it.

Or split it into two explicit layers (if both are present they override
`palm_tree.png`):

| File | What it is | Notes |
|------|------------|-------|
| `palm_back.png` | Trunk + anything **behind** the falling fruit. | Anchored **bottom-centre** at `palm_pos`. |
| `palm_front.png` | Just the **big front fronds** the fruit emerges from behind. | Anchored **centre**, over the top of the trunk. |

Put `leaf_spawn` (Inspector) inside the frond mass so coconuts appear from the tree.

### Fruit

| File | What it is | Notes |
|------|------------|-------|
| `coconut.png` | The coconut. Roughly round. | Square canvas, ≥96px. Drawn `fruit_px` (46) wide on screen. |
| `banana.png` | The banana (the quick back-to-back cues). | Same treatment. Can reuse the coconut art at first. |

### Monkey — CENTRE-BOTTOM, facing the viewer, arms up ready to catch

Draw all four on the **same size canvas** with his **feet in the same spot**, so
they swap cleanly. Anchored **bottom-centre** at `monkey_pos`. ~320×360.

| File | Pose | When |
|------|------|------|
| `monkey_idle.png` | Neutral, waiting, hands up and open. | default |
| `monkey_catch.png` | Clean catch — holding the coconut overhead, pleased. | **Perfect** (coconut) |
| `monkey_catch_banana.png` | *(optional)* clean catch holding a banana. Falls back to `monkey_catch.png`. | **Perfect** (banana) |
| `monkey_bobble.png` | Fumble — hands splayed, wincing at the escaping fruit. | **Good** |
| `monkey_hit.png` | Bonked — head knocked back, dazed (leave room above for stars). | **Miss** |
| `monkey_clap.png` | Claps overhead -- empty-handed press, nothing to catch. | **empty press** |

Canvas sizes no longer need to match — each pose is auto-normalised by its opaque
width and anchored by the bottom of its opaque pixels, so a pose drawn on a
bigger sheet still renders the monkey at the same size and foot position. Keeping
the body roughly the same *within* each frame still helps.

The code adds motion on top of the still (squash on catch, shake on bobble,
recoil+tilt on hit), so a single drawing per pose already feels animated. Want
real frame-by-frame later? swap to an `AnimatedSprite2D` — ask and I'll wire it.

### Effects (optional — code draws fallbacks)

| File | What it is |
|------|------------|
| `stars.png` | The "bonk" burst above the monkey's head on a Miss (stars / tweeting birds). Small, ~120×80. |
| `dust.png` | Little puff where a bobbled coconut lands. ~80×50. |

**Minimum set to see the whole design:** `background`, `palm_back`, `palm_front`,
`coconut`, `monkey_idle`, `monkey_catch`, `monkey_bobble`, `monkey_hit`.

## Positioning knobs (CoconutGame node, Inspector)

- `palm_pos`, `monkey_pos`, `ground_y` — place the pieces.
- `leaf_spawn` — the point the fruit appears from (put it just behind `palm_front`).
- `hands_offset`, `head_offset` — catch point / bonk point, relative to `monkey_pos`.
- `deflect_offset` — where a bobbled fruit lands, relative to the hands.
- `fruit_px`, `palm_scale`, `monkey_scale` — sizes (source resolution doesn't matter).

---

## Paper drawing -> transparent PNG

### 1. Draw for easy cut-out
- One object per sheet. Bold, closed **ink** outline (fineliner/marker — not
  pencil, too faint). Solid fills where you want it opaque.
- Bright, even light; tape the page flat so it doesn't curl or cast a shadow.
- Leave a white margin all around.

### 2. Capture
- A scanner app (Adobe Scan, Microsoft Lens, Apple Notes "Scan Documents")
  de-skews and boosts contrast — better than a raw photo. Export the page image.

### 3. Knock out the white  — pick one

**Photopea** (free, browser, photoshop-like) — fastest
1. Open the image. `Image ▸ Adjustments ▸ Levels`, pull the black and white
   sliders in so the paper is pure white and lines are solid.
2. `Layer ▸ (right-click) ▸ Rasterize`, then `Select ▸ Color Range`, click the
   white, raise Fuzziness until the page is selected — `Delete`.
3. `Image ▸ Trim` (transparent pixels) to crop tight.
4. `Image ▸ Image Size` down to the target (e.g. monkey 360 px tall).
5. `File ▸ Export as ▸ PNG`.

**GIMP** (free, desktop)
1. `Layer ▸ Transparency ▸ Add Alpha Channel`.
2. `Colors ▸ Color to Alpha…`, pick white → white becomes transparent *and* your
   edges get a soft anti-aliased fade (nicer than a hard wand delete).
3. `Image ▸ Crop to Content`. `File ▸ Export As…` → `.png`.

**Krita** (free) — `Filter ▸ Colors ▸ Color to Alpha` (white), then
`Image ▸ Trim to Current Layer`, `File ▸ Export`.

**Inkscape** (free) — best if your art is clean lines / flat colour and you want
razor-sharp edges at any size: `File ▸ Import` the scan, select it,
`Path ▸ Trace Bitmap` (brightness cutoff; or "multicolour" for flats), delete the
original photo, tidy nodes, `File ▸ Export` (PNG, transparent by default).

**remove.bg / AI cut-out** — okay for a solid monkey silhouette, but it eats thin
frond tips and outlines. Use it as a first pass, then clean up by hand.

**Tablet route** — if you have an iPad/tablet, just re-draw over your paper photo
on a transparent layer in Procreate/Krita and export. No background removal at all.

### 4. Godot import
Select the PNG in the FileSystem dock → **Import** tab:
- **Fix Alpha Border**: ON (kills white halos on the edges).
- **Filter**: ON for smooth painted art, OFF for crisp/pixel art.
- **Mipmaps**: ON if the image is much larger than it's drawn.
Click **Reimport**.
