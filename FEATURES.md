# Picolo — Features & Functions of a Modern Photo Editing App

This document surveys what modern photo editing applications do, and defines
which of those capabilities belong in Picolo. Picolo is **not** trying to be
Photoshop, Lightroom, or Pixelmator. Its entire reason to exist is the
**round-trip**: you have an image on your clipboard or desktop, you need it a
little better in ten seconds, and you want it back on the clipboard without
launching a heavyweight editor.

```
paste / drop  →  adjust  →  copy / drag out
      (the whole product, measured in seconds)
```

Every feature below is judged against that loop. If a feature slows the loop
down, adds a mode, or demands a mental model beyond "sliders on the right,
image in the middle", it does not belong — no matter how standard it is
elsewhere.

---

## 1. The anatomy of a modern photo editor

Modern editors, from Apple Photos to Lightroom, converge on the same feature
families. This is the landscape Picolo curates from:

### 1.1 Tonal adjustments
The bread and butter — how light or dark things are.

| Function | What it does | In Picolo |
|---|---|---|
| Exposure | Scales scene light in EV stops | ✅ Shipped |
| Brightness | Linear lift/drop of all pixels | ✅ Shipped |
| Contrast | Expands/compresses tonal range around mid-gray | ✅ Shipped |
| Highlights / Shadows | Recovers blown skies, lifts dark areas independently | ✅ Shipped |
| Levels | Black point / white point / gamma remap with histogram | ✅ Shipped (histogram control with draggable handles) |
| Curves | Arbitrary tone remap per channel | ❌ Idea only — powerful but slow to use; levels covers 90% of cases |
| Clarity / structure | Local (mid-frequency) contrast | 🔜 Planned |

### 1.2 Color adjustments
How colors look — warmth, intensity, cast.

| Function | What it does | In Picolo |
|---|---|---|
| Saturation | Global color intensity | ✅ Shipped |
| Vibrance | Saturation that protects already-saturated tones and skin | 🔜 Planned |
| Temperature | Warm ↔ cool white balance | ✅ Shipped |
| Tint | Green ↔ magenta axis (pairs with temperature) | 🔜 Planned |
| Hue rotation | Shifts every hue around the wheel | 🔜 Planned |
| Black & white | Monochrome conversion, ideally with channel mixing | 🔜 Planned |
| Color balance | Per-tonal-range color shifts (shadows/mids/highlights) | 🔜 Planned |
| HSL per-color panels | Adjust each color band separately | ❌ Too heavy — this is where "quick" dies |

### 1.3 Effects & finishing
Stylization applied after tone and color are right.

| Function | What it does | In Picolo |
|---|---|---|
| Sharpen / unsharp mask | Edge crispness, essential for screenshots & downscales | 🔜 Planned |
| Gaussian blur | Uniform softening (also great for redacting backgrounds) | 🔜 Planned |
| Motion / zoom blur | Directional or radial streaking | ✅ Motion shipped; zoom planned |
| Vignette | Darkened corners to focus the eye | 🔜 Planned |
| Grain / noise | Film texture, also masks banding | 🔜 Planned |
| Sepia / duotone / posterize / invert | One-slider stylized looks | 🔜 Planned |
| Preset "looks" / filters | One-click Instagram-style combinations | ❌ Idea only — only if built purely from existing adjustments |
| Layers, masks, brushes | Local editing | ❌ Never — the line Picolo will not cross |
| Healing / clone / AI object removal | Content-aware retouching | ❌ Never |
| Text / annotations / shapes | Markup | ❌ Never — macOS Preview and screenshot markup already do this |

### 1.4 Geometry
Changing the frame itself. This is the biggest current gap — cropping is the
single most common edit after brightness, and Picolo can't do it yet.

| Function | What it does | In Picolo |
|---|---|---|
| Crop (free + fixed ratios) | Trim the frame; 1:1, 4:3, 16:9 presets | 🔜 Planned — top priority |
| Rotate 90° / flip | Orientation fixes | 🔜 Planned |
| Straighten | Small-angle rotation with auto-crop | 🔜 Planned |
| Resize / scale | Output at target dimensions | 🔜 Planned |
| Perspective correction | Keystone fixes | 🔜 Planned (low priority) |

### 1.5 Input / output
For Picolo this **is** the product — a modern editor lives or dies on how
frictionless getting pixels in and out is.

| Function | In Picolo |
|---|---|
| Paste from clipboard (⌘V) | ✅ Shipped |
| Drag & drop in | ✅ Shipped |
| Open file / open-with / launch-with-file | ✅ Shipped |
| Copy edited result (⌘C) at full resolution | ✅ Shipped |
| Drag edited result out as a file other apps accept | ✅ Shipped |
| Save / Save As (PNG) | ✅ Shipped |
| JPEG / HEIC / WebP export with quality control | 🔜 Planned |
| EXIF preserve/strip choice | 🔜 Planned |
| Copy at chosen resolution (e.g. @1x from a Retina screenshot) | 🔜 Planned |
| Recent files | 🔜 Planned |
| Batch / multi-file queue | ❌ Idea only — likely scope creep |

### 1.6 Workflow & safety
What makes an editor feel trustworthy.

| Function | In Picolo |
|---|---|
| Non-destructive editing (original never mutated) | ✅ Core architecture |
| Reset one control (double-click) / reset all (⌘R) | ✅ Shipped |
| Undo / redo | 🔜 Planned — expected by every user, must ship |
| Before/after compare (hold a key to peek at the original) | 🔜 Planned |
| Copy/paste adjustment settings between images | 🔜 Planned |
| Saveable presets | ❌ Idea only |
| Auto-enhance (one click) | ❌ Idea only — attractive but results are unpredictable |

---

## 2. What "modern UI, great UX" means for Picolo

Modern doesn't mean more chrome — it means the app feels native, immediate,
and legible. Concrete principles:

### Immediate feedback
- **Live preview on every slider tick.** Rendering already happens on
  `adjustments.didSet`; it must stay under one frame for typical images
  (downscale the preview render if needed — outputs always re-render from the
  full-res original anyway).
- **A live histogram** that reflects the current edit, not just the source,
  so levels/exposure work feels informed rather than guessed.

### Direct manipulation over abstraction
- The histogram-with-handles levels control is the model: **manipulate the
  data, not a number**. Extend that spirit — crop by dragging on the canvas,
  straighten by dragging a horizon line, temperature via a warm↔cool tinted
  slider track.
- Double-click-to-reset on every control, everywhere, consistently.

### Keyboard-first round-trip
The core loop must be doable without touching the mouse:
⌘V paste → adjust (arrow-key nudge on a focused slider) → ⌘C copy → done.
Every menu action keeps a shortcut; new features must justify theirs.

### Native macOS feel
- SwiftUI materials, vibrancy, correct light/dark appearance, SF Symbols.
- System conventions: `.onDrag`/`.onDrop`, standard Open/Save panels,
  proper menu bar, an app icon and About panel.
- **Never a modal wizard, never a floating tool palette.** One window,
  canvas center, inspector right.

### Legible state
- Show image dimensions and zoom % somewhere quiet.
- Checkerboard behind transparency so PNGs read correctly.
- Real (but lightweight) error surfaces where a beep isn't enough —
  e.g. a failed save must not be silent.

### Forgiveness
- Undo/redo across all adjustments.
- Before/after held-key compare.
- Non-destructive always: the original is sacred, every edit is revocable.

---

## 3. The dividing line

A one-sentence test for any proposed feature:

> **Does it make the paste→edit→copy loop better, or does it make Picolo a
> smaller Photoshop?**

Ships: anything that is one slider, one drag, or one keystroke and applies to
the whole image. Never ships: anything requiring selections, layers, brushes,
type tools, or a second window. When in doubt, leave it out — the user who
needs it has Photoshop; the user who has Picolo needs speed.
