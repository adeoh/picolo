# Picolo Roadmap

Planned work, ordered by milestone. Keep with the product goal: **fast
round-trip editing** (paste → edit → copy) — only add adjustments that are
common and quick. Resist anything that turns Picolo into a heavyweight editor.
See `FEATURES.md` for the full feature philosophy and the ships/never-ships line.

Status legend: `[ ]` planned · `[~]` in progress · `[x]` done

## Shipped (v0.1)

- [x] Paste / drag-in / open; copy / drag-out / save (PNG)
- [x] Exposure, Brightness, Contrast
- [x] Highlights / Shadows
- [x] Saturation, Temperature
- [x] Levels (histogram + input/output/gamma handles)
- [x] Motion blur (strength + direction)
- [x] Non-destructive pipeline, per-control and global reset

## Milestone 1 — Trust the tool (v0.2)

The features whose absence makes users hesitate. Undo and crop are the two
most-expected functions in any editor; error feedback makes failures visible.

- [ ] Undo / redo (⌘Z / ⇧⌘Z) across all adjustment changes
- [ ] Crop (freeform + fixed aspect ratios, drag directly on canvas)
- [ ] Rotate 90° left/right, flip horizontal / vertical
- [ ] Before/after compare (hold a key to peek at the original)
- [ ] Real error UI where a beep isn't enough (failed save/open must not be silent)
- [ ] Checkerboard backing for transparency

## Milestone 2 — Modern canvas & UX polish (v0.3)

Make the one window feel first-class and native.

- [ ] Zoom in/out + fit-to-window, pan when zoomed
- [ ] Image dimensions + zoom % readout
- [ ] Live histogram that reflects current adjustments (not just source)
- [ ] Keyboard nudge on focused slider (arrow keys; keyboard-first round-trip)
- [ ] App icon + About panel
- [ ] Dark/light appropriate chrome, SwiftUI materials pass
- [ ] Fullscreen / distraction-free mode

## Milestone 3 — Output flexibility (v0.4)

The "copy out" half of the loop, beyond always-PNG.

- [ ] Export as JPEG (with quality slider)
- [ ] Export as HEIC / WebP
- [ ] Choose output format on save
- [ ] Copy at chosen resolution (e.g. @1x from a Retina screenshot)
- [ ] Preserve/strip metadata (EXIF) on export
- [ ] Open recent files
- [ ] Preferences window (default format, quality)

## Milestone 4 — Rounding out adjustments (v0.5)

One-slider, whole-image adjustments only. Each follows the "adding a filter"
conventions below.

### Tone & color
- [ ] Vibrance (saturation that protects skin tones)
- [ ] Tint (green↔magenta, paired with existing temperature)
- [ ] Clarity / structure (local contrast)
- [ ] Black & white / monochrome with channel mix
- [ ] Hue rotation
- [ ] Color balance (shadows / midtones / highlights)

### Effects
- [ ] Sharpen / unsharp mask
- [ ] Gaussian blur (single strength slider)
- [ ] Vignette (amount + radius)
- [ ] Grain / noise (amount)
- [ ] Zoom / radial blur (complements motion blur)
- [ ] Sepia / duotone
- [ ] Posterize
- [ ] Invert

### Geometry
- [ ] Straighten / rotate by angle (with auto-crop)
- [ ] Resize / scale to dimensions

## Milestone 5 — Workflow (v0.6)

- [ ] Copy/paste adjustment settings between images
- [ ] Reset individual groups (not just single sliders / all)

## Ideas (unsorted, may not fit the "minimal" goal)

- [ ] One-click auto-enhance
- [ ] Preset filters (only if built purely from existing adjustments)
- [ ] Save & load adjustment presets
- [ ] Curves (RGB + per-channel)
- [ ] Perspective correction
- [ ] Drag multiple files (basic batch queue)
- [ ] Selective / brushed adjustments — probably over the line; see FEATURES.md

## Conventions for adding a filter

1. Add the field(s) to `Adjustments.swift` with **neutral defaults** so the
   identity transform is preserved.
2. Insert the Core Image stage in `apply(to:)`, skipping it when neutral.
3. Add a `SliderRow` (or custom control) to the right group in `AdjustmentsPanel.swift`.
4. Watch the linear-vs-display-space trap for any tonal/color-matrix work
   (see the Levels notes in `CLAUDE.md`).
