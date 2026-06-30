# Picolo Roadmap

Upcoming features, tracked as checklists. Keep with the product goal: **fast
round-trip editing** — only add adjustments that are common and quick. Resist
anything that turns Picolo into a heavyweight editor.

Status legend: `[ ]` planned · `[~]` in progress · `[x]` done

## Filters & Effects

### Shipped
- [x] Exposure
- [x] Brightness / Contrast
- [x] Highlights / Shadows
- [x] Saturation
- [x] Temperature
- [x] Levels (histogram + input/output/gamma handles)
- [x] Motion blur (strength + direction)

### Planned
- [ ] Gaussian blur (single strength slider)
- [ ] Sharpen / unsharp mask
- [ ] Vignette (amount + radius)
- [ ] Grain / noise (amount)
- [ ] Tint (hue shift, paired with existing temperature)
- [ ] Vibrance (saturation that protects skin tones)
- [ ] Clarity / structure (local contrast)
- [ ] Black & white / monochrome with channel mix
- [ ] Sepia / duotone
- [ ] Invert
- [ ] Hue rotation
- [ ] Color balance (shadows / midtones / highlights)
- [ ] Posterize
- [ ] Zoom / radial blur (complements motion blur)

### Ideas (unsorted, may not fit the "minimal" goal)
- [ ] One-click auto-enhance
- [ ] Preset filters (Instagram-style looks)
- [ ] Curves (RGB + per-channel)
- [ ] Selective / brushed adjustments

## Conventions for adding a filter
1. Add the field(s) to `Adjustments.swift` with **neutral defaults** so the
   identity transform is preserved.
2. Insert the Core Image stage in `apply(to:)`, skipping it when neutral.
3. Add a `SliderRow` (or custom control) to the right group in `AdjustmentsPanel.swift`.
4. Watch the linear-vs-display-space trap for any tonal/color-matrix work
   (see the Levels notes in `CLAUDE.md`).
