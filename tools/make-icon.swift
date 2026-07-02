// Generates Resources/Picolo.icns — run from the repo root:
//   swiftc -sdk "$(xcrun --show-sdk-path)" tools/make-icon.swift -o /tmp/make-icon && /tmp/make-icon
// Design: macOS squircle, indigo-to-midnight gradient, three adjustment
// sliders (Picolo's whole UI in one glyph) with a warm accent knob.
import AppKit

let designSize: CGFloat = 1024

func draw(into ctx: CGContext, pixels: CGFloat) {
    let s = pixels / designSize
    ctx.scaleBy(x: s, y: s)

    // Canonical macOS icon: content squircle inset ~10% on each side.
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let radius: CGFloat = 185
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Soft drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 36,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Background gradient: indigo → midnight.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let bg = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.33, green: 0.27, blue: 0.75, alpha: 1),
        CGColor(red: 0.13, green: 0.11, blue: 0.32, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: rect.maxY),
                           end: CGPoint(x: 512, y: rect.minY), options: [])

    // Faint top sheen.
    let sheen = CGGradient(colorsSpace: space, colors: [
        CGColor(gray: 1, alpha: 0.18), CGColor(gray: 1, alpha: 0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: rect.maxY),
                           end: CGPoint(x: 512, y: rect.maxY - 300), options: [])

    // Three slider rows: track + knob. Knob positions stagger; the middle
    // knob is the warm accent (temperature).
    let trackX: CGFloat = 240, trackW: CGFloat = 544, trackH: CGFloat = 34
    let rows: [(y: CGFloat, knob: CGFloat, warm: Bool)] = [
        (652, 0.72, false),
        (494, 0.34, true),
        (336, 0.55, false),
    ]
    for row in rows {
        let track = CGRect(x: trackX, y: row.y - trackH / 2, width: trackW, height: trackH)
        ctx.addPath(CGPath(roundedRect: track, cornerWidth: trackH / 2,
                           cornerHeight: trackH / 2, transform: nil))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.22))
        ctx.fillPath()

        let knobR: CGFloat = 56
        let cx = trackX + trackW * row.knob
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18,
                      color: CGColor(gray: 0, alpha: 0.4))
        ctx.setFillColor(row.warm
            ? CGColor(red: 1.0, green: 0.72, blue: 0.32, alpha: 1)
            : CGColor(gray: 0.98, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: cx - knobR, y: row.y - knobR,
                                   width: knobR * 2, height: knobR * 2))
        ctx.restoreGState()
    }
    ctx.restoreGState()
}

func writePNG(pixels: Int, to url: URL) {
    let ctx = CGContext(data: nil, width: pixels, height: pixels,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(into: ctx, pixels: CGFloat(pixels))
    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("Resources/Picolo.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    writePNG(pixels: base, to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(pixels: base * 2, to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o",
                  root.appendingPathComponent("Resources/Picolo.icns").path]
try! task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "wrote Resources/Picolo.icns" : "iconutil failed")
