<h1 align="center">Picolo</h1>

<p align="center">
  <strong>A minimal native macOS image editor built around one loop:</strong><br>
  paste or drop an image in → adjust → copy or drag it straight back out.
</p>

<p align="center">
  <a href="https://github.com/adeoh/picolo/releases/latest"><img alt="Download" src="https://img.shields.io/github/v/release/adeoh/picolo?label=download&style=for-the-badge"></a>
  <img alt="Platform" src="https://img.shields.io/badge/macOS-13%2B-black?style=for-the-badge">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-orange?style=for-the-badge">
</p>

---

## Download

**[⬇︎ Download the latest Picolo.app](https://github.com/adeoh/picolo/releases/latest)**

Unzip, drag `Picolo.app` to `/Applications`, and open it.

The app is **ad-hoc signed**, not notarized — macOS will complain the first time.
Right-click `Picolo.app` → **Open** → **Open**, or run once:

```bash
xattr -dr com.apple.quarantine /Applications/Picolo.app
```

Requires macOS 13 Ventura or later. Universal on whatever Mac built it — build from source for a native binary on yours.

---

## Why

Most of the time you don't need Photoshop. You need an image on your clipboard to be
*a little better* in ten seconds and back on your clipboard. That's the entire product:

```
paste / drop  →  adjust  →  copy / drag out
```

Every feature is judged against that loop. Anything that adds a mode, a mental model,
or a wait doesn't ship.

## Features

**Tone** — Exposure, Brightness, Contrast, Clarity, Highlights, Shadows
**Levels** — histogram control with draggable black / gamma / white handles, plus output range
**Color** — Saturation, Vibrance, Temperature, Tint, Hue, and a black & white channel mixer
**Detail** — Sharpen, Grain, Gaussian / Motion / Zoom blur
**Effects** — Vignette, Sepia, Posterize, Invert
**Geometry** — Crop, Rotate, Flip, Straighten

Plus: live histogram, zoom & pan, undo/redo, copy & paste adjustments between images,
per-group reset, recents, PNG / JPEG / HEIC export with scale and EXIF control.

Editing is **non-destructive** — the original is never touched, and copy / save / drag-out
always re-render from it at full resolution.

## Shortcuts

| | |
|---|---|
| `⌘V` / `⌘C` | paste image in / copy edited image out |
| `⌘O` `⌘S` `⇧⌘S` | open, save, save as |
| `⌘Z` `⇧⌘Z` | undo, redo |
| `⌘+` `⌘-` `⌘0` `⌘1` | zoom in, out, fit, actual size |
| `⌘K` | crop |
| `[` `]` | rotate left / right |
| `⇧⌘H` `⇧⌘J` | flip horizontal / vertical |
| `⌥⌘C` `⌥⌘V` | copy / paste adjustments |
| `⌘R` | reset all adjustments |

Double-click any slider's value to reset just that control. Double-click a levels handle
to reset just that handle.

## Build from source

No Xcode needed — Picolo is a Swift Package, so the Command Line Tools are enough.

```bash
git clone https://github.com/adeoh/picolo.git
cd picolo
./build-app.sh          # release build + assembled, ad-hoc-signed Picolo.app
open Picolo.app
```

`swift build` alone gives the fastest compile-error loop, but always launch the assembled
bundle for real testing — the raw binary has no dock icon, menus, or window focus.

## Under the hood

SwiftUI + AppKit for the shell, Core Image for the pixels. A single `EditorModel` owns
all state and I/O; the views are thin observers. Adjustments are a value type whose
defaults form the identity transform, applied as a fixed Core Image filter chain.

See [`CLAUDE.md`](CLAUDE.md) for the architecture notes and [`FEATURES.md`](FEATURES.md)
for what's deliberately *not* in Picolo.
