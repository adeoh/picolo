import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

/// Output encoding for save / copy / drag-out.
enum ExportFormat: String, CaseIterable, Identifiable {
    case png, jpeg, heic

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        }
    }
    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        }
    }
    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        }
    }
    var isLossy: Bool { self != .png }
}

/// Central state for the editor: the loaded image, the live adjustments, and
/// all I/O (open, save, clipboard, drag in/out). The view layer observes this.
@MainActor
final class EditorModel: ObservableObject {
    /// Single instance shared by the App scene and the app delegate (which
    /// needs it for open-file events).
    static let shared = EditorModel()

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
    /// Canvas zoom: nil = fit to window, otherwise an absolute scale where
    /// 1.0 shows one image pixel per point (100%).
    @Published var zoom: Double?
    /// Pan offset in canvas points, only meaningful while zoomed.
    @Published var panOffset: CGSize = .zero
    /// The fit scale the canvas last used, reported back so the zoom readout
    /// and the zoom in/out steps have a concrete number in fit mode.
    @Published var fitScale: Double = 1

    // Export settings. Live values used by save/copy/drag, persisted so they
    // double as the user's defaults across launches (Preferences edits the
    // same values).
    @Published var exportFormat: ExportFormat {
        didSet { UserDefaults.standard.set(exportFormat.rawValue, forKey: "exportFormat") }
    }
    @Published var exportQuality: Double {
        didSet { UserDefaults.standard.set(exportQuality, forKey: "exportQuality") }
    }
    /// Output scale multiplier: 1 = source pixels, 0.5 = @1x from Retina, etc.
    @Published var exportScale: Double {
        didSet { UserDefaults.standard.set(exportScale, forKey: "exportScale") }
    }
    @Published var preserveMetadata: Bool {
        didSet { UserDefaults.standard.set(preserveMetadata, forKey: "preserveMetadata") }
    }
    /// EXIF/TIFF/GPS/IPTC dictionaries of the source file, when it had any.
    private var sourceMetadata: [String: Any]?
    var hasSourceMetadata: Bool { sourceMetadata != nil }

    @Published private(set) var recentFiles: [URL] = []
    /// Live luminance histogram, normalized to 0...1, in display space. It
    /// reflects every adjustment *except* the levels remap itself, so the
    /// levels handles keep pointing at the tones they operate on.
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
        let d = UserDefaults.standard
        exportFormat = ExportFormat(rawValue: d.string(forKey: "exportFormat") ?? "") ?? .png
        exportQuality = d.object(forKey: "exportQuality") as? Double ?? 0.9
        exportScale = d.object(forKey: "exportScale") as? Double ?? 1
        preserveMetadata = d.bool(forKey: "preserveMetadata")
        recentFiles = (d.stringArray(forKey: "recentFiles") ?? []).map { URL(fileURLWithPath: $0) }
        installKeyMonitor()
    }

    private func noteRecent(_ url: URL) {
        var files = recentFiles.filter { $0.path != url.path }
        files.insert(url, at: 0)
        recentFiles = Array(files.prefix(10))
        UserDefaults.standard.set(recentFiles.map(\.path), forKey: "recentFiles")
    }

    func clearRecents() {
        recentFiles = []
        UserDefaults.standard.removeObject(forKey: "recentFiles")
    }

    // MARK: - Loading

    func load(ciImage: CIImage, url: URL? = nil) {
        let img = ciImage.cropped(to: ciImage.extent)
        original = img
        fileURL = url
        pixelSize = img.extent.size
        zoom = nil
        panOffset = .zero
        sourceMetadata = nil
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
        // The histogram recomputes on every slider tick; a ~512px proxy is
        // statistically identical and keeps the reduce pass cheap.
        var image = image
        let maxDim = max(image.extent.width, image.extent.height)
        if maxDim > 512 {
            let s = 512 / maxDim
            image = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
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
        // applyOrientationProperty bakes EXIF rotation in, so camera photos
        // load upright and our own orientation state starts from .up.
        guard let img = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            errorMessage = "Couldn't open “\(url.lastPathComponent)” — the file isn't a readable image."
            return
        }
        load(ciImage: img, url: url)
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
            sourceMetadata = props
        }
        noteRecent(url)
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
        guard let original else { preview = nil; histogram = []; return }
        let edited = adjustments.apply(to: original)
        guard let cg = context.createCGImage(edited, from: edited.extent) else { return }
        preview = NSImage(cgImage: cg, size: edited.extent.size)
        pixelSize = edited.extent.size
        // Histogram of the pre-levels edit: exposure/contrast/etc. move the
        // bars live, while the levels stage still sees "its" input tones.
        let preLevels = adjustments.apply(to: original, includeLevels: false)
        histogram = Self.computeHistogram(of: preLevels, context: context)
    }

    /// Renders the current edit as a CGImage at the export scale.
    func renderCGImage() -> CGImage? {
        guard let original else { return nil }
        var edited = adjustments.apply(to: original)
        if exportScale != 1 {
            let f = CIFilter.lanczosScaleTransform()
            f.inputImage = edited
            f.scale = Float(exportScale)
            f.aspectRatio = 1
            edited = f.outputImage ?? edited
        }
        return context.createCGImage(edited, from: edited.extent)
    }

    /// Encodes the current edit in the chosen export format, carrying the
    /// source EXIF/GPS/IPTC across when the user opted to keep metadata.
    func renderExportData() -> Data? {
        guard let cg = renderCGImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, exportFormat.utType.identifier as CFString, 1, nil) else { return nil }

        var props: [String: Any] = [:]
        if exportFormat.isLossy {
            props[kCGImageDestinationLossyCompressionQuality as String] = exportQuality
        }
        if preserveMetadata, let sourceMetadata {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary,
                        kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary] {
                if let value = sourceMetadata[key as String] { props[key as String] = value }
            }
            // Rotation is baked into the pixels; a stale EXIF orientation
            // would make other apps double-rotate.
            if var tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                tiff[kCGImagePropertyTIFFOrientation as String] = 1
                props[kCGImagePropertyTIFFDictionary as String] = tiff
            }
        }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    // MARK: - Undo / redo

    var canUndo: Bool { pendingUndoBase != nil || !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func recordUndo(from oldValue: Adjustments) {
        guard !isRestoringAdjustments, oldValue != adjustments else { return }
        trackNudgeTarget(from: oldValue)
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

    // MARK: - Zoom

    private static let zoomSteps: [Double] = [0.05, 0.1, 0.25, 0.33, 0.5, 0.67,
                                              1, 1.5, 2, 3, 4, 6, 8]

    /// The scale currently on screen (fit mode reports the canvas fit scale).
    var effectiveZoom: Double { zoom ?? fitScale }

    func zoomIn() {
        guard hasImage else { return }
        let current = effectiveZoom
        setZoom(Self.zoomSteps.first(where: { $0 > current * 1.001 }) ?? current)
    }

    func zoomOut() {
        guard hasImage else { return }
        let current = effectiveZoom
        setZoom(Self.zoomSteps.last(where: { $0 < current * 0.999 }) ?? current)
    }

    func zoomToFit() {
        zoom = nil
        panOffset = .zero
    }

    func zoomToActualSize() { setZoom(1) }

    private func setZoom(_ new: Double) {
        // Keep the same image point centered: pan scales with the zoom.
        let old = effectiveZoom
        if old > 0 {
            let f = new / old
            panOffset = CGSize(width: panOffset.width * f, height: panOffset.height * f)
        }
        zoom = new
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

    // MARK: - Keyboard nudge

    /// One entry per slider-backed value, so arrow keys can fine-tune the
    /// control the user touched last without any focus-ring ceremony.
    private struct NudgeTarget {
        let get: (Adjustments) -> Double
        let set: (inout Adjustments, Double) -> Void
        let range: ClosedRange<Double>
    }

    private static let nudgeTargets: [NudgeTarget] = [
        .init(get: { $0.exposure }, set: { $0.exposure = $1 }, range: -3...3),
        .init(get: { $0.brightness }, set: { $0.brightness = $1 }, range: -1...1),
        .init(get: { $0.contrast }, set: { $0.contrast = $1 }, range: 0.25...4),
        .init(get: { $0.saturation }, set: { $0.saturation = $1 }, range: 0...2),
        .init(get: { $0.highlights }, set: { $0.highlights = $1 }, range: 0...1),
        .init(get: { $0.shadows }, set: { $0.shadows = $1 }, range: -1...1),
        .init(get: { $0.temperature }, set: { $0.temperature = $1 }, range: -2000...2000),
        .init(get: { $0.tint }, set: { $0.tint = $1 }, range: -150...150),
        .init(get: { $0.vibrance }, set: { $0.vibrance = $1 }, range: -1...1),
        .init(get: { $0.hueRotation }, set: { $0.hueRotation = $1 }, range: -180...180),
        .init(get: { $0.clarity }, set: { $0.clarity = $1 }, range: 0...1),
        .init(get: { $0.monoR }, set: { $0.monoR = $1 }, range: 0...1),
        .init(get: { $0.monoG }, set: { $0.monoG = $1 }, range: 0...1),
        .init(get: { $0.monoB }, set: { $0.monoB = $1 }, range: 0...1),
        .init(get: { $0.sharpen }, set: { $0.sharpen = $1 }, range: 0...2),
        .init(get: { $0.gaussianBlur }, set: { $0.gaussianBlur = $1 }, range: 0...50),
        .init(get: { $0.motionBlurRadius }, set: { $0.motionBlurRadius = $1 }, range: 0...100),
        .init(get: { $0.motionBlurAngle }, set: { $0.motionBlurAngle = $1 }, range: -180...180),
        .init(get: { $0.zoomBlur }, set: { $0.zoomBlur = $1 }, range: 0...40),
        .init(get: { $0.vignette }, set: { $0.vignette = $1 }, range: 0...1),
        .init(get: { $0.vignetteRadius }, set: { $0.vignetteRadius = $1 }, range: 0...2),
        .init(get: { $0.grain }, set: { $0.grain = $1 }, range: 0...1),
        .init(get: { $0.sepia }, set: { $0.sepia = $1 }, range: 0...1),
        .init(get: { $0.posterize }, set: { $0.posterize = $1 }, range: 0...14),
        .init(get: { $0.straightenAngle }, set: { $0.straightenAngle = $1 }, range: -15...15),
        .init(get: { $0.inputBlack }, set: { $0.inputBlack = $1 }, range: 0...1),
        .init(get: { $0.inputWhite }, set: { $0.inputWhite = $1 }, range: 0...1),
        .init(get: { $0.midtones }, set: { $0.midtones = $1 }, range: 0.1...3),
        .init(get: { $0.outputBlack }, set: { $0.outputBlack = $1 }, range: 0...1),
        .init(get: { $0.outputWhite }, set: { $0.outputWhite = $1 }, range: 0...1),
    ]

    private var lastNudgeIndex: Int?

    private func trackNudgeTarget(from oldValue: Adjustments) {
        let changed = Self.nudgeTargets.indices.filter {
            Self.nudgeTargets[$0].get(oldValue) != Self.nudgeTargets[$0].get(adjustments)
        }
        // Exactly one value moved = a slider interaction; bulk changes
        // (reset, undo, geometry) shouldn't retarget the arrows.
        if changed.count == 1 { lastNudgeIndex = changed[0] }
    }

    private func nudge(by direction: Double, coarse: Bool) -> Bool {
        guard let index = lastNudgeIndex else { return false }
        let target = Self.nudgeTargets[index]
        let span = target.range.upperBound - target.range.lowerBound
        let step = span / (coarse ? 20 : 100) * direction
        let value = min(max(target.get(adjustments) + step, target.range.lowerBound),
                        target.range.upperBound)
        target.set(&adjustments, value)
        return true
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
        // ← / → nudge the last-touched slider (⇧ for a coarser step).
        if event.type == .keyDown, hasImage, !isCropping,
           event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           event.keyCode == 123 || event.keyCode == 124 {
            let direction: Double = event.keyCode == 124 ? 1 : -1
            return nudge(by: direction, coarse: event.modifierFlags.contains(.shift))
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
        guard let cg = renderCGImage() else { NSSound.beep(); return }
        let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
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

    /// Saves over the source file when the chosen format matches it,
    /// otherwise prompts so a format switch never clobbers the original.
    func save() {
        guard let url = fileURL else { saveAs(); return }
        let ext = url.pathExtension.lowercased()
        let matches = ext == exportFormat.fileExtension
            || (exportFormat == .jpeg && ext == "jpeg")
        if matches { write(to: url) } else { saveAs() }
    }

    func saveAs() {
        guard hasImage else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [exportFormat.utType]
        let base = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.nameFieldStringValue = base + "." + exportFormat.fileExtension
        if panel.runModal() == .OK, let url = panel.url {
            write(to: url)
            fileURL = url
            noteRecent(url)
        }
    }

    private func write(to url: URL) {
        guard let data = renderExportData() else {
            errorMessage = "Couldn't render the image for saving."
            return
        }
        do { try data.write(to: url) } catch {
            errorMessage = "Couldn't save to “\(url.lastPathComponent)”: \(error.localizedDescription)"
        }
    }

    // MARK: - Drag out

    /// Writes the current render to a temp file in the export format and
    /// returns a provider that drops a file other apps accept as an image.
    func dragProvider() -> NSItemProvider? {
        guard let data = renderExportData() else { return nil }
        let name = (fileURL?.deletingPathExtension().lastPathComponent ?? "Picolo")
            + "." + exportFormat.fileExtension
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url) } catch { return nil }
        let provider = NSItemProvider()
        provider.suggestedName = name
        provider.registerFileRepresentation(forTypeIdentifier: exportFormat.utType.identifier,
                                             fileOptions: [],
                                             visibility: .all) { completion in
            completion(url, true, nil)
            return nil
        }
        return provider
    }
}
