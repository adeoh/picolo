import SwiftUI

/// The crop-mode canvas overlay: dims everything outside the draft selection,
/// draws a rule-of-thirds grid inside it, and exposes drag handles plus a small
/// toolbar with aspect presets and Apply / Cancel. The draft lives in
/// `model.cropDraft`, normalized (0…1, top-left origin) to the displayed image.
struct CropOverlay: View {
    @ObservedObject var model: EditorModel
    /// Frame of the displayed image within the canvas, in canvas coordinates.
    let imageRect: CGRect

    @State private var dragStart: CGRect?
    @State private var aspect: AspectPreset = .free

    enum AspectPreset: String, CaseIterable, Identifiable {
        case free = "Free", square = "1:1", fourThree = "4:3", threeTwo = "3:2", sixteenNine = "16:9"
        var id: String { rawValue }
        /// Width:height in displayed pixels, nil = unconstrained.
        var ratio: CGFloat? {
            switch self {
            case .free: nil
            case .square: 1
            case .fourThree: 4.0 / 3.0
            case .threeTwo: 3.0 / 2.0
            case .sixteenNine: 16.0 / 9.0
            }
        }
    }

    private let minSize: CGFloat = 0.05  // normalized minimum crop dimension

    var body: some View {
        let sel = viewRect(model.cropDraft)

        ZStack {
            dimming(around: sel)

            // Selection border + thirds grid.
            Path { p in p.addRect(sel) }
                .stroke(.white, lineWidth: 1)
            thirdsGrid(in: sel)
                .stroke(.white.opacity(0.35), lineWidth: 0.5)

            // Move the whole selection by dragging inside it.
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: sel.width, height: sel.height)
                .position(x: sel.midX, y: sel.midY)
                .gesture(moveGesture())

            ForEach(activeHandles) { handle in
                handleDot(at: handle.point(in: sel))
                    .gesture(resizeGesture(handle))
            }

            toolbar
                .position(x: imageRect.midX, y: imageRect.maxY + 24)
        }
        .onChange(of: aspect) { newValue in
            if let r = newValue.ratio { snapDraft(toRatio: r) }
        }
    }

    // MARK: - Chrome

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $aspect) {
                ForEach(AspectPreset.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()

            Button("Cancel") { model.cancelCrop() }
                .controlSize(.small)
            Button("Apply") { model.commitCrop() }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func dimming(around sel: CGRect) -> some View {
        Path { p in
            p.addRect(imageRect)
            p.addRect(sel)
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
    }

    private func thirdsGrid(in sel: CGRect) -> Path {
        Path { p in
            for i in 1...2 {
                let x = sel.minX + sel.width * CGFloat(i) / 3
                p.move(to: CGPoint(x: x, y: sel.minY)); p.addLine(to: CGPoint(x: x, y: sel.maxY))
                let y = sel.minY + sel.height * CGFloat(i) / 3
                p.move(to: CGPoint(x: sel.minX, y: y)); p.addLine(to: CGPoint(x: sel.maxX, y: y))
            }
        }
    }

    private func handleDot(at point: CGPoint) -> some View {
        Circle()
            .fill(.white)
            .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 0.5))
            .frame(width: 10, height: 10)
            .contentShape(Circle().inset(by: -10))
            .position(point)
    }

    // MARK: - Handles

    private struct Handle: Identifiable {
        let id: String
        let dx: CGFloat  // -1 left edge, 0 center, 1 right edge
        let dy: CGFloat  // -1 top edge, 0 center, 1 bottom edge
        func point(in r: CGRect) -> CGPoint {
            CGPoint(x: r.midX + dx * r.width / 2, y: r.midY + dy * r.height / 2)
        }
    }

    private var activeHandles: [Handle] {
        let corners = [Handle(id: "nw", dx: -1, dy: -1), Handle(id: "ne", dx: 1, dy: -1),
                       Handle(id: "sw", dx: -1, dy: 1), Handle(id: "se", dx: 1, dy: 1)]
        // Edge handles would break a locked aspect, so they only exist in Free.
        let edges = [Handle(id: "n", dx: 0, dy: -1), Handle(id: "s", dx: 0, dy: 1),
                     Handle(id: "w", dx: -1, dy: 0), Handle(id: "e", dx: 1, dy: 0)]
        return aspect == .free ? corners + edges : corners
    }

    // MARK: - Gestures

    private func moveGesture() -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStart ?? model.cropDraft
                dragStart = start
                var d = start
                d.origin.x = clamp(start.minX + value.translation.width / imageRect.width,
                                   0, 1 - start.width)
                d.origin.y = clamp(start.minY + value.translation.height / imageRect.height,
                                   0, 1 - start.height)
                model.cropDraft = d
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resizeGesture(_ handle: Handle) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStart ?? model.cropDraft
                dragStart = start
                let tx = value.translation.width / imageRect.width
                let ty = value.translation.height / imageRect.height
                model.cropDraft = resized(start, handle: handle, tx: tx, ty: ty)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resized(_ start: CGRect, handle: Handle, tx: CGFloat, ty: CGFloat) -> CGRect {
        var minX = start.minX, maxX = start.maxX
        var minY = start.minY, maxY = start.maxY

        if handle.dx < 0 { minX = clamp(start.minX + tx, 0, maxX - minSize) }
        if handle.dx > 0 { maxX = clamp(start.maxX + tx, minX + minSize, 1) }
        if handle.dy < 0 { minY = clamp(start.minY + ty, 0, maxY - minSize) }
        if handle.dy > 0 { maxY = clamp(start.maxY + ty, minY + minSize, 1) }

        var r = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        // Locked aspect: derive height from width (ratio is in *view pixels*,
        // normalized units need the image frame's own aspect factored in),
        // anchored at the corner opposite the one being dragged.
        if let ratio = aspect.ratio, handle.dx != 0, handle.dy != 0 {
            let normRatio = ratio * imageRect.height / imageRect.width
            var h = r.width / normRatio
            if h > 1 { h = 1; r.size.width = h * normRatio }
            r.size.height = h
            if handle.dy < 0 { r.origin.y = maxY - h }
            // Keep in bounds vertically, shrinking if the anchor pins us.
            if r.minY < 0 {
                let overflow = -r.minY
                r.origin.y = 0
                r.size.height -= overflow
                r.size.width = r.height * normRatio
                if handle.dx < 0 { r.origin.x = maxX - r.width }
            }
            if r.maxY > 1 {
                let overflow = r.maxY - 1
                r.size.height -= overflow
                r.size.width = r.height * normRatio
                if handle.dx < 0 { r.origin.x = maxX - r.width }
            }
        }
        return r
    }

    /// Centers the current draft on the nearest rect with the given ratio.
    private func snapDraft(toRatio ratio: CGFloat) {
        let normRatio = ratio * imageRect.height / imageRect.width
        var d = model.cropDraft
        let center = CGPoint(x: d.midX, y: d.midY)
        if d.width / d.height > normRatio {
            d.size.width = d.height * normRatio
        } else {
            d.size.height = d.width / normRatio
        }
        d.origin = CGPoint(x: clamp(center.x - d.width / 2, 0, 1 - d.width),
                           y: clamp(center.y - d.height / 2, 0, 1 - d.height))
        model.cropDraft = d
    }

    // MARK: - Mapping

    private func viewRect(_ norm: CGRect) -> CGRect {
        CGRect(x: imageRect.minX + norm.minX * imageRect.width,
               y: imageRect.minY + norm.minY * imageRect.height,
               width: norm.width * imageRect.width,
               height: norm.height * imageRect.height)
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), max(lo, hi))
    }
}
