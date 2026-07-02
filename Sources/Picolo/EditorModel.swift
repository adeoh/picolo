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
        didSet {
            scheduleRender()
            recordUndo(from: oldValue)
        }
    }
    /// The rendered preview shown in the canvas.
    @Published private(set) var preview: NSImage?
    /// While true the canvas shows the unadjusted original (geometry kept),
    /// driven by holding the B key — a Lightroom-style before/after peek.
    @Published private(set) var showOriginal = false
    /// Rendered "before" image used while `showOriginal` is on.
    private var beforePreview: NSImage?
    /// Crop mode: when true the canvas shows the crop overlay instead of the
    /// plain preview. `cropDraft` is the pending selection, normalized to the
    /// displayed image with a top-left origin (view space, unlike CI space).
    @Published var isCropping = false
    @Published var cropDraft = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// Non-nil presents a modal error alert (real failures only; transient
    /// misses like an empty pasteboard still just beep).
    @Published var errorMessage: String?
    /// Luminance histogram of the source, normalized to 0...1, in display space.
    @Published private(set) var histogram: [Float] = []
    /// Source file URL, when the image came from / was saved to disk.
    @Published private(set) var fileURL: URL?
    @Published private(set) var pixelSize: CGSize = .zero

    private let context = CIContext(options: [.useSoftwareRenderer: false])

    // Undo/redo: snapshots of `adjustments`. Rapid changes (slider drags)
    // coalesce into one step — the pre-drag value is held in `pendingUndoBase`
    // until changes go quiet for a beat, then committed as a single entry.
    private var undoStack: [Adjustments] = []
    private var redoStack: [Adjustments] = []
    private var pendingUndoBase: Adjustments?
    private var undoCommitTask: Task<Void, Never>?
    private var isRestoringAdjustments = false

    private var keyMonitor: Any?

    var hasImage: Bool { original != nil }

    init() {
        installKeyMonitor()
    }

    // MARK: - Loading

    func load(ciImage: CIImage, url: URL? = nil) {
        let img = ciImage.cropped(to: ciImage.extent)
        original = img
        fileURL = url
        pixelSize = img.extent.size
        histogram = Self.computeHistogram(of: img, context: context)
        // A fresh image starts a fresh history; the reset to neutral must not
        // itself land on the undo stack.
        undoCommitTask?.cancel()
        undoStack.removeAll()
        redoStack.removeAll()
        pendingUndoBase = nil
        isCropping = false
        showOriginal = false
        isRestoringAdjustments = true
        adjustments = .neutral // triggers render
        isRestoringAdjustments = false
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
            errorMessage = "Couldn't open “\(url.lastPathComponent)” — the file isn't a readable image."
            return
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

    // MARK: - Undo / redo

    var canUndo: Bool { pendingUndoBase != nil || !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func recordUndo(from oldValue: Adjustments) {
        guard !isRestoringAdjustments, oldValue != adjustments else { return }
        redoStack.removeAll()
        if pendingUndoBase == nil { pendingUndoBase = oldValue }
        undoCommitTask?.cancel()
        undoCommitTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.commitPendingUndo()
        }
    }

    private func commitPendingUndo() {
        undoCommitTask?.cancel()
        if let base = pendingUndoBase, base != adjustments {
            undoStack.append(base)
        }
        pendingUndoBase = nil
    }

    func undo() {
        commitPendingUndo()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(adjustments)
        isRestoringAdjustments = true
        adjustments = previous
        isRestoringAdjustments = false
    }

    func redo() {
        commitPendingUndo()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(adjustments)
        isRestoringAdjustments = true
        adjustments = next
        isRestoringAdjustments = false
    }

    // MARK: - Editing helpers

    func reset() { adjustments = .neutral }

    func rotateLeft() { adjustments.rotate(clockwise: false) }
    func rotateRight() { adjustments.rotate(clockwise: true) }
    func flipHorizontal() { adjustments.flip(horizontal: true) }
    func flipVertical() { adjustments.flip(horizontal: false) }

    // MARK: - Crop

    func beginCrop() {
        guard hasImage else { return }
        cropDraft = CGRect(x: 0, y: 0, width: 1, height: 1)
        isCropping = true
    }

    func cancelCrop() { isCropping = false }

    /// Applies `cropDraft` (view space: normalized, y-down, relative to the
    /// currently displayed image) by composing it with any existing crop in
    /// CI space (normalized, y-up, relative to the oriented full image).
    func commitCrop() {
        guard isCropping else { return }
        isCropping = false
        let d = cropDraft
        guard d.width > 0.001, d.height > 0.001,
              d != CGRect(x: 0, y: 0, width: 1, height: 1) else { return }
        let c = adjustments.cropRect
        let yUp = 1 - d.maxY
        adjustments.cropRect = CGRect(x: c.minX + d.minX * c.width,
                                      y: c.minY + yUp * c.height,
                                      width: d.width * c.width,
                                      height: d.height * c.height)
    }

    // MARK: - Before/after peek

    private func setShowOriginal(_ show: Bool) {
        guard hasImage else { return }
        if show, !showOriginal {
            // "Before" keeps geometry (crop/rotation) so the frame doesn't
            // jump — only the tonal/color work drops out.
            var geometryOnly = Adjustments()
            geometryOnly.orientation = adjustments.orientation
            geometryOnly.cropRect = adjustments.cropRect
            if let original {
                let before = geometryOnly.apply(to: original)
                if let cg = context.createCGImage(before, from: before.extent) {
                    beforePreview = NSImage(cgImage: cg, size: before.extent.size)
                }
            }
        }
        showOriginal = show
    }

    /// The image the canvas should display right now.
    var displayImage: NSImage? { showOriginal ? (beforePreview ?? preview) : preview }

    // MARK: - Key handling (hold-to-compare, crop confirm/cancel)

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        // Hold B to compare with the original.
        if event.charactersIgnoringModifiers?.lowercased() == "b",
           event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           hasImage {
            if event.type == .keyDown, !event.isARepeat { setShowOriginal(true) }
            if event.type == .keyUp { setShowOriginal(false) }
            return true
        }
        // Return applies / Escape cancels an active crop.
        if isCropping, event.type == .keyDown {
            if event.keyCode == 36 || event.keyCode == 76 { commitCrop(); return true }  // return / enter
            if event.keyCode == 53 { cancelCrop(); return true }                          // esc
        }
        return false
    }

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
        guard let data = renderPNGData() else {
            errorMessage = "Couldn't render the image for saving."
            return
        }
        do { try data.write(to: url) } catch {
            errorMessage = "Couldn't save to “\(url.lastPathComponent)”: \(error.localizedDescription)"
        }
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
