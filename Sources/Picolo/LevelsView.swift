import SwiftUI

/// Histogram-based levels control: the source histogram with draggable input
/// handles (black / gamma / white) along the top and output handles (black /
/// white) along the bottom — the same affordance as the Photoshop levels box.
struct LevelsView: View {
    @ObservedObject var model: EditorModel
    @Environment(\.colorScheme) private var scheme

    private let boxHeight: CGFloat = 104
    private let handleStrip: CGFloat = 14   // space above/below the histogram for handles

    private var boxFill: Color { scheme == .dark ? Color(white: 0.12) : Color(white: 0.97) }
    private var boxBorder: Color { scheme == .dark ? Color(white: 0.28) : Color(white: 0.75) }
    private var barFill: Color { scheme == .dark ? Color(white: 0.5) : Color(white: 0.55) }
    private var guideLine: Color { scheme == .dark ? Color(white: 0.32) : Color(white: 0.72) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let plotRect = CGRect(x: 0, y: handleStrip, width: w,
                                  height: boxHeight - handleStrip * 2)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(boxFill)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(boxBorder))

                HistogramShape(bins: model.histogram)
                    .fill(barFill)
                    .frame(width: plotRect.width, height: plotRect.height)
                    .offset(x: plotRect.minX, y: plotRect.minY)

                // Faint guide lines dropping from the input handles.
                ForEach(inputGuides(width: w), id: \.self) { x in
                    Rectangle()
                        .fill(guideLine)
                        .frame(width: 1, height: plotRect.height)
                        .offset(x: x, y: plotRect.minY)
                }

                handles(width: w)
            }
            .frame(height: boxHeight)
        }
        .frame(height: boxHeight)
    }

    // MARK: - Handles

    @ViewBuilder
    private func handles(width w: CGFloat) -> some View {
        let a = model.adjustments

        // Input black (top-left), white (top-right), midtone (between them).
        triangle(x: a.inputBlack * w, y: handleStrip / 2, fill: .black)
            .gesture(drag { p in setInputBlack(p / w) })
            .onTapGesture(count: 2) { model.adjustments.inputBlack = 0 }

        triangle(x: midtoneX(width: w), y: handleStrip / 2, fill: Color(white: 0.55))
            .gesture(drag { p in setMidtone(p, width: w) })
            .onTapGesture(count: 2) { model.adjustments.midtones = 1 }

        triangle(x: a.inputWhite * w, y: handleStrip / 2, fill: .white)
            .gesture(drag { p in setInputWhite(p / w) })
            .onTapGesture(count: 2) { model.adjustments.inputWhite = 1 }

        // Output black / white along the bottom.
        circle(x: a.outputBlack * w, y: boxHeight - handleStrip / 2, fill: .black)
            .gesture(drag { p in setOutputBlack(p / w) })
            .onTapGesture(count: 2) { model.adjustments.outputBlack = 0 }

        circle(x: a.outputWhite * w, y: boxHeight - handleStrip / 2, fill: .white)
            .gesture(drag { p in setOutputWhite(p / w) })
            .onTapGesture(count: 2) { model.adjustments.outputWhite = 1 }
    }

    private func triangle(x: CGFloat, y: CGFloat, fill: Color) -> some View {
        DownTriangle()
            .fill(fill)
            .overlay(DownTriangle().stroke(Color(white: 0.6), lineWidth: 0.5))
            .frame(width: 11, height: 9)
            .contentShape(Rectangle().inset(by: -8))
            .position(x: x, y: y)
    }

    private func circle(x: CGFloat, y: CGFloat, fill: Color) -> some View {
        Circle()
            .fill(fill)
            .overlay(Circle().stroke(Color(white: 0.6), lineWidth: 0.5))
            .frame(width: 9, height: 9)
            .contentShape(Circle().inset(by: -8))
            .position(x: x, y: y)
    }

    private func drag(_ update: @escaping (CGFloat) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { update($0.location.x) }
    }

    // MARK: - Value <-> position mapping

    private func inputGuides(width w: CGFloat) -> [CGFloat] {
        [model.adjustments.inputBlack * w, midtoneX(width: w), model.adjustments.inputWhite * w]
    }

    /// The gamma handle sits at the input value that maps to mid-gray: 0.5^γ,
    /// scaled into the current [black, white] window.
    private func midtoneX(width w: CGFloat) -> CGFloat {
        let a = model.adjustments
        let span = max(a.inputWhite - a.inputBlack, 0.0001)
        let rel = pow(0.5, a.midtones)
        return CGFloat(a.inputBlack + span * rel) * w
    }

    private func setInputBlack(_ v: Double) {
        model.adjustments.inputBlack = clamp(v, 0, model.adjustments.inputWhite - 0.01)
    }
    private func setInputWhite(_ v: Double) {
        model.adjustments.inputWhite = clamp(v, model.adjustments.inputBlack + 0.01, 1)
    }
    private func setMidtone(_ px: CGFloat, width w: CGFloat) {
        let a = model.adjustments
        let span = max(a.inputWhite - a.inputBlack, 0.0001)
        let rel = clamp((Double(px / w) - a.inputBlack) / span, 0.005, 0.995)
        model.adjustments.midtones = clamp(log(rel) / log(0.5), 0.1, 3)
    }
    private func setOutputBlack(_ v: Double) {
        model.adjustments.outputBlack = clamp(v, 0, model.adjustments.outputWhite - 0.01)
    }
    private func setOutputWhite(_ v: Double) {
        model.adjustments.outputWhite = clamp(v, model.adjustments.outputBlack + 0.01, 1)
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), max(lo, hi))
    }
}

/// Filled area chart of the histogram bins (0 at bottom, 1 at top).
private struct HistogramShape: Shape {
    let bins: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard bins.count > 1 else { return path }
        let step = rect.width / CGFloat(bins.count - 1)
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        for (i, v) in bins.enumerated() {
            let x = CGFloat(i) * step
            let y = rect.maxY - CGFloat(max(0, min(1, v))) * rect.height
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A downward-pointing triangle (apex at the bottom), for the input handles.
private struct DownTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
