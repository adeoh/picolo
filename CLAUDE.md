# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What Picolo is

Picolo is a minimal native macOS image editor. The whole product goal is **speed of round-trip**: paste or drag an image in, apply basic adjustments (exposure, brightness, contrast, gamma, highlights/shadows, saturation, temperature), then copy or drag the edited image straight back out into another app. Keep features minimal — resist adding anything that isn't a fast, common adjustment.

## Toolchain constraint (important)

**Xcode is not installed on this machine — only the Command Line Tools.** `xcodebuild` will fail. This is why the project is a **Swift Package Manager executable**, not an `.xcodeproj`. Do not introduce an Xcode project or anything that requires `xcodebuild`. SwiftUI, AppKit, and Core Image all come from the macOS SDK and work fine under `swift build`.

## Build & run

```bash
swift build                  # compile (debug); fastest feedback loop for catching errors
./build-app.sh               # build release + assemble & ad-hoc-sign Picolo.app
./build-app.sh debug         # same, debug config
open Picolo.app              # launch the assembled app
```

There is no test target yet. To sanity-check Core Image pipeline changes without the GUI, compile a throwaway script against the SDK:
`swiftc -sdk "$(xcrun --show-sdk-path)" file.swift -o /tmp/probe && /tmp/probe`.

Running the raw SwiftPM binary directly (`.build/.../Picolo`) does **not** give proper window focus, menus, or a dock icon — always launch via the assembled `Picolo.app` for real testing. `build-app.sh` ad-hoc signs the bundle so Gatekeeper allows a locally built app to run.

## Architecture

A single `EditorModel` (`@MainActor`, `ObservableObject`) owns all state and I/O; the SwiftUI views are thin and observe it. Data flow is one-directional:

```
input (open / paste / drop)  →  EditorModel.original : CIImage
                                       │
slider edits → EditorModel.adjustments (didSet) → scheduleRender()
                                       │
                          Adjustments.apply(to:) → CIContext → preview : NSImage
                                       │
output (copy / save / drag-out) renders original+adjustments at FULL resolution
```

Key files in `Sources/Picolo/`:

- **`Adjustments.swift`** — a value type holding every edit with **neutral defaults that form the identity transform** (`Adjustments() == .neutral`). `apply(to:)` chains Core Image filters in a fixed order: exposure → color controls → highlight/shadow → temperature → levels, then crops back to the source extent. Add new adjustments here and in `AdjustmentsPanel`. **Levels gotcha:** Core Image's working space is linear light, but levels sliders are display-referred (0…1 == the gamma-encoded pixel), so the levels stage encodes to sRGB (`linearToSRGBToneCurve`), does its matrix/gamma math, then decodes back (`sRGBToneCurveToLinear`). Without that wrap, an Input Black of 0.25 would clip mid-gray to black. Any new tonal remap built on `CIColorMatrix` has the same trap.
- **`EditorModel.swift`** — source of truth. Holds `original` (unedited `CIImage`), live `adjustments`, the rendered `preview`, and the source `histogram`. The `preview` is what's shown; **outputs (copy/save/drag) always re-render from `original` at full resolution**, never from the preview. The histogram is computed once per loaded image via `CIAreaHistogram` (encoded to sRGB first, same display-space reasoning as levels) and normalized to 0…1. Single reusable GPU-backed `CIContext`. Loading also handled at launch via `.onOpenURL`.
- **`LevelsView.swift`** — the histogram-based levels control (replaces plain sliders for the Levels group). Draws `model.histogram` as a filled area chart with draggable input handles (black / gamma / white triangles on top) and output handles (black / white circles on the bottom). Handle x-positions map straight to the 0…1 adjustment values; the gamma handle sits at `0.5^midtones` within the `[inputBlack, inputWhite]` window (inverse: `midtones = log(rel)/log(0.5)`). Double-click any handle to reset just that one.
- **`ImageCanvas.swift`** — center view. Displays `preview`, accepts drops (`.onDrop`), and is a drag *source* (`.onDrag` → `model.dragProvider()`). Drag-out writes a temp PNG and vends it as a file provider so other apps accept it as an image.
- **`AdjustmentsPanel.swift`** — right inspector of sliders. Double-tapping a slider's value readout resets that one control to neutral.
- **`PicoloApp.swift`** — `@main` App + the menu/keyboard commands (⌘O open, ⌘S save, ⇧⌘S save-as, ⌘C copy image, ⌘V paste image, ⌘R reset).

## Conventions & gotchas

- **Swift 6 strict concurrency is on.** `NSImage` is not `Sendable`, so never capture it across actor boundaries — extract `Data` (which is `Sendable`) inside async/loader closures and pass that to the `@MainActor`. See `ImageCanvas.handleDrop` and `EditorModel.load(imageData:)`.
- Editing is **non-destructive**: never mutate `original`; all edits live in `adjustments` and are reapplied on render.
- Save currently always exports **PNG**. `save()` overwrites the source file if there is one, otherwise falls through to `saveAs()`.
- I/O failures surface as `NSSound.beep()` rather than throwing/alerting — keep that lightweight feedback pattern unless building real error UI.
