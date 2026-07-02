import SwiftUI
import UniformTypeIdentifiers

/// The central canvas: shows the preview, accepts drops, and is itself a drag
/// source so the edited image can be pulled into another app.
struct ImageCanvas: View {
    @ObservedObject var model: EditorModel
    @State private var dropTargeted = false

    var body: some View {
        ZStack {
            CheckerboardBackground()

            if let display = model.displayImage {
                GeometryReader { geo in
                    let fit = Self.fitRect(imageSize: display.size, in: geo.size, inset: 16)
                    image(display, in: fit)
                    if model.isCropping {
                        CropOverlay(model: model, imageRect: fit)
                    }
                    if model.showOriginal {
                        Text("BEFORE")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                            .position(x: geo.size.width / 2, y: 24)
                    }
                }
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
    private func image(_ nsImage: NSImage, in fit: CGRect) -> some View {
        let base = Image(nsImage: nsImage)
            .resizable()
            .frame(width: fit.width, height: fit.height)
            .position(x: fit.midX, y: fit.midY)
        // Drag-out conflicts with the crop handles, so it pauses in crop mode.
        if model.isCropping {
            base
        } else {
            base.onDrag { model.dragProvider() ?? NSItemProvider() }
        }
    }

    /// Aspect-fit `imageSize` into `container` with a margin on all sides.
    static func fitRect(imageSize: CGSize, in container: CGSize, inset: CGFloat) -> CGRect {
        let avail = CGSize(width: max(container.width - inset * 2, 1),
                           height: max(container.height - inset * 2, 1))
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: CGPoint(x: inset, y: inset), size: avail)
        }
        let scale = min(avail.width / imageSize.width, avail.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2,
                      y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
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
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 12
            let light = Color(white: 0.22)
            let dark = Color(white: 0.16)
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
