import SwiftUI
import UniformTypeIdentifiers

/// The central canvas: shows the preview, accepts drops, and is itself a drag
/// source so the edited image can be pulled into another app.
struct ImageCanvas: View {
    @ObservedObject var model: EditorModel
    @State private var dropTargeted = false
    @State private var panStart: CGSize?
    @State private var magnifyStart: Double?

    var body: some View {
        ZStack {
            CheckerboardBackground()

            if let display = model.displayImage {
                GeometryReader { geo in
                    let fitScale = Self.fitScale(imageSize: display.size, in: geo.size, inset: 16)
                    let rect = imageRect(size: display.size, canvas: geo.size, fitScale: fitScale)
                    image(display, in: rect)
                    if model.isCropping {
                        CropOverlay(model: model, imageRect: rect)
                    }
                    if model.showOriginal {
                        Text("BEFORE")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .position(x: geo.size.width / 2, y: 24)
                    }
                    readout
                        .position(x: geo.size.width / 2, y: geo.size.height - 18)
                    Color.clear
                        .onAppear { model.fitScale = fitScale }
                        .onChange(of: fitScale) { model.fitScale = $0 }
                }
                .clipped()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 42, weight: .thin))
                    Text("Drag an image here, or press ⌘V to paste")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
            }
        }
        .onDrop(of: [.fileURL, .image, .png, .tiff], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    @ViewBuilder
    private func image(_ nsImage: NSImage, in rect: CGRect) -> some View {
        let base = Image(nsImage: nsImage)
            .resizable()
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .gesture(magnifyGesture)
        // Drag-out conflicts with the crop handles and with panning, so it
        // only runs in plain fit mode.
        if model.isCropping {
            base
        } else if model.zoom != nil {
            base.gesture(panGesture)
        } else {
            base.onDrag { model.dragProvider() ?? NSItemProvider() }
        }
    }

    private var readout: some View {
        Text("\(Int(model.pixelSize.width)) × \(Int(model.pixelSize.height)) px · \(Int((model.effectiveZoom * 100).rounded()))%")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - Zoom / pan geometry

    static func fitScale(imageSize: CGSize, in container: CGSize, inset: CGFloat) -> Double {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return min(max(container.width - inset * 2, 1) / imageSize.width,
                   max(container.height - inset * 2, 1) / imageSize.height)
    }

    /// Where the image sits in the canvas: centered at fit scale, or scaled
    /// and panned (with the pan clamped so the image never fully escapes).
    private func imageRect(size: CGSize, canvas: CGSize, fitScale: Double) -> CGRect {
        let scale = model.zoom ?? fitScale
        let w = size.width * scale, h = size.height * scale
        let offset = model.zoom == nil ? .zero : clampedPan(model.panOffset,
                                                            imageSize: CGSize(width: w, height: h),
                                                            canvas: canvas)
        return CGRect(x: (canvas.width - w) / 2 + offset.width,
                      y: (canvas.height - h) / 2 + offset.height,
                      width: w, height: h)
    }

    /// Axes where the image fits stay centered; overflowing axes clamp so the
    /// image edge can't cross the canvas midline gap.
    private func clampedPan(_ pan: CGSize, imageSize: CGSize, canvas: CGSize) -> CGSize {
        func clampAxis(_ v: CGFloat, image: CGFloat, avail: CGFloat) -> CGFloat {
            guard image > avail else { return 0 }
            let limit = (image - avail) / 2 + 16
            return min(max(v, -limit), limit)
        }
        return CGSize(width: clampAxis(pan.width, image: imageSize.width, avail: canvas.width),
                      height: clampAxis(pan.height, image: imageSize.height, avail: canvas.height))
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = panStart ?? model.panOffset
                panStart = start
                model.panOffset = CGSize(width: start.width + value.translation.width,
                                         height: start.height + value.translation.height)
            }
            .onEnded { _ in panStart = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let start = magnifyStart ?? model.effectiveZoom
                magnifyStart = start
                model.zoom = min(max(start * value, 0.05), 8)
            }
            .onEnded { _ in magnifyStart = nil }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.load(url: url) }
            }
            return true
        }

        for type in [UTType.png, .tiff, .image] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in model.load(imageData: data) }
            }
            return true
        }

        return false
    }
}

/// Classic transparency checkerboard so transparent images read clearly.
private struct CheckerboardBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 12
            let light = scheme == .dark ? Color(white: 0.22) : Color(white: 0.93)
            let dark = scheme == .dark ? Color(white: 0.16) : Color(white: 0.86)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(dark))
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = (row % 2 == 0) ? 0 : tile
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: tile, height: tile)),
                                 with: .color(light))
                    x += tile * 2
                }
                y += tile
                row += 1
            }
        }
    }
}
