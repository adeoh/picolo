import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

/// Central state for the editor: the loaded image, the live adjustments, and
/// all I/O (open, save, clipboard, drag in/out). The view layer observes this.
@MainActor
final class EditorModel: ObservableObject {
    /// The unedited source image. Nil when nothing is loaded.
    @Published private(set) var original: CIImage?
    /// Live adjustment values; mutating any of these re-renders the preview.
    @Published var adjustments = Adjustments() {
        didSet { scheduleRender() }
    }
    /// The rendered preview shown in the canvas.
    @Published private(set) var preview: NSImage?
    /// Luminance histogram of the source, normalized to 0...1, in display space.
    @Published private(set) var histogram: [Float] = []
    /// Source file URL, when the image came from / was saved to disk.
    @Published private(set) var fileURL: URL?
    @Published private(set) var pixelSize: CGSize = .zero

    private let context = CIContext(options: [.useSoftwareRenderer: false])

    var hasImage: Bool { original != nil }

    // MARK: - Loading

    func load(ciImage: CIImage, url: URL? = nil) {
        let img = ciImage.cropped(to: ciImage.extent)
        original = img
        fileURL = url
        pixelSize = img.extent.size
        histogram = Self.computeHistogram(of: img, context: context)
        adjustments = .neutral // triggers render
    }

    /// Builds a normalized luminance histogram in display (sRGB) space so the
    /// bars line up with the tones the user perceives and the levels handles.
    private static func computeHistogram(of image: CIImage, context: CIContext,
                                         bins: Int = 128) -> [Float] {
        let encode = CIFilter.linearToSRGBToneCurve()
        encode.inputImage = image
        guard let encoded = encode.outputImage else { return [] }

        let hist = CIFilter.areaHistogram()
        hist.inputImage = encoded
        hist.extent = encoded.extent
        hist.scale = 20
        hist.count = bins
        guard let out = hist.outputImage else { return [] }

        var buffer = [Float](repeating: 0, count: bins * 4)
        context.render(out, toBitmap: &buffer,
                       rowBytes: bins * 4 * MemoryLayout<Float>.size,
                       bounds: CGRect(x: 0, y: 0, width: bins, height: 1),
                       format: .RGBAf, colorSpace: nil)

        var lum = [Float](repeating: 0, count: bins)
        for i in 0..<bins {
            let r = buffer[i * 4], g = buffer[i * 4 + 1], b = buffer[i * 4 + 2]
            lum[i] = (r + g + b) / 3
        }
        let peak = lum.max() ?? 0
        if peak > 0 { for i in lum.indices { lum[i] /= peak } }
        return lum
    }

    func load(url: URL) {
        guard let img = CIImage(contentsOf: url) else {
            NSSound.beep(); return
        }
        load(ciImage: img, url: url)
    }

    func load(nsImage: NSImage) {
        guard let tiff = nsImage.tiffRepresentation,
              let ci = CIImage(data: tiff) else { NSSound.beep(); return }
        load(ciImage: ci)
    }

    func load(imageData: Data) {
        guard let ci = CIImage(data: imageData) else { NSSound.beep(); return }
        load(ciImage: ci)
    }

    // MARK: - Rendering

    private func scheduleRender() {
        guard let original else { preview = nil; return }
        let edited = adjustments.apply(to: original)
        guard let cg = context.createCGImage(edited, from: edited.extent) else { return }
        preview = NSImage(cgImage: cg, size: edited.extent.size)
    }

    /// Renders the current edit at full resolution as a CGImage.
    func renderCGImage() -> CGImage? {
        guard let original else { return nil }
        let edited = adjustments.apply(to: original)
        return context.createCGImage(edited, from: edited.extent)
    }

    func renderPNGData() -> Data? {
        guard let cg = renderCGImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Editing helpers

    func reset() { adjustments = .neutral }

    // MARK: - Clipboard

    func paste() {
        let pb = NSPasteboard.general
        if let images = pb.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           let img = images.first {
            load(nsImage: img)
        } else if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL],
                  let url = urls.first {
            load(url: url)
        } else {
            NSSound.beep()
        }
    }

    func copy() {
        guard let png = renderPNGData(), let img = NSImage(data: png) else {
            NSSound.beep(); return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([img])
    }

    // MARK: - Disk I/O

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { load(url: url) }
    }

    /// Saves over the source file when possible, otherwise prompts.
    func save() {
        guard let url = fileURL else { saveAs(); return }
        write(to: url)
    }

    func saveAs() {
        guard hasImage else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        if panel.runModal() == .OK, let url = panel.url {
            write(to: url)
            fileURL = url
        }
    }

    private func write(to url: URL) {
        guard let data = renderPNGData() else { NSSound.beep(); return }
        do { try data.write(to: url) } catch { NSSound.beep() }
    }

    // MARK: - Drag out

    /// Writes the current render to a temp PNG and returns a provider that
    /// drops a file other apps can accept as an image.
    func dragProvider() -> NSItemProvider? {
        guard let data = renderPNGData() else { return nil }
        let name = (fileURL?.deletingPathExtension().lastPathComponent ?? "Picolo") + ".png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url) } catch { return nil }
        let provider = NSItemProvider()
        provider.suggestedName = name
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier,
                                             fileOptions: [],
                                             visibility: .all) { completion in
            completion(url, true, nil)
            return nil
        }
        return provider
    }
}
