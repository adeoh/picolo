// Generates Resources/Picolo.icns from Resources/icon.svg — run from the repo root:
//   swiftc -sdk "$(xcrun --show-sdk-path)" tools/make-icon.swift -o /tmp/make-icon && /tmp/make-icon
// NSImage reads SVG natively on macOS 13+, so no rsvg/inkscape needed.
import AppKit

let root = FileManager.default.currentDirectoryPath
let svgURL = URL(fileURLWithPath: root).appendingPathComponent("Resources/icon.svg")

guard let art = NSImage(contentsOf: svgURL) else {
    FileHandle.standardError.write(Data("cannot read \(svgURL.path)\n".utf8))
    exit(1)
}

/// Draws the artwork into a square canvas, fitted to the canonical macOS
/// content box (~82% of the canvas, centered).
func render(pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let canvas = CGFloat(pixels)
    let box = canvas * 0.82
    let scale = min(box / art.size.width, box / art.size.height)
    let w = art.size.width * scale, h = art.size.height * scale
    art.draw(in: NSRect(x: (canvas - w) / 2, y: (canvas - h) / 2, width: w, height: h))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Picolo.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for (scale, suffix) in [(1, ""), (2, "@2x")] {
        guard let png = render(pixels: size * scale) else { exit(1) }
        try png.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}

let icns = URL(fileURLWithPath: root).appendingPathComponent("Resources/Picolo.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(task.terminationStatus) }

print("✓ wrote \(icns.path)")
