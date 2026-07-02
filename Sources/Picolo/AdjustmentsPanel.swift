import SwiftUI

/// One labelled slider row with a reset-on-double-click value readout.
private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let neutral: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .onTapGesture(count: 2) { value = neutral }
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }
}

/// The right-hand inspector with all adjustment sliders.
struct AdjustmentsPanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                group("Tone") {
                    SliderRow(title: "Exposure", value: $model.adjustments.exposure, range: -3...3, neutral: 0)
                    SliderRow(title: "Brightness", value: $model.adjustments.brightness, range: -1...1, neutral: 0)
                    SliderRow(title: "Contrast", value: $model.adjustments.contrast, range: 0.25...4, neutral: 1)
                }
                group("Light") {
                    SliderRow(title: "Highlights", value: $model.adjustments.highlights, range: 0...1, neutral: 1)
                    SliderRow(title: "Shadows", value: $model.adjustments.shadows, range: -1...1, neutral: 0)
                }
                group("Levels") {
                    LevelsView(model: model)
                }
                group("Color") {
                    SliderRow(title: "Saturation", value: $model.adjustments.saturation, range: 0...2, neutral: 1)
                    SliderRow(title: "Temperature", value: $model.adjustments.temperature, range: -2000...2000, neutral: 0)
                }
                group("Effects") {
                    SliderRow(title: "Motion Blur", value: $model.adjustments.motionBlurRadius, range: 0...100, neutral: 0)
                    SliderRow(title: "Blur Angle", value: $model.adjustments.motionBlurAngle, range: -180...180, neutral: 0)
                }
                group("Export") {
                    pickerRow("Format") {
                        Picker("", selection: $model.exportFormat) {
                            ForEach(ExportFormat.allCases) { Text($0.displayName).tag($0) }
                        }
                    }
                    pickerRow("Scale") {
                        Picker("", selection: $model.exportScale) {
                            Text("3×").tag(3.0)
                            Text("2×").tag(2.0)
                            Text("1× (100%)").tag(1.0)
                            Text("½×").tag(0.5)
                            Text("¼×").tag(0.25)
                        }
                    }
                    if model.exportFormat.isLossy {
                        SliderRow(title: "Quality", value: $model.exportQuality, range: 0.1...1, neutral: 0.9)
                    }
                    Toggle("Keep metadata (EXIF)", isOn: $model.preserveMetadata)
                        .font(.system(size: 11))
                        .controlSize(.small)
                        .disabled(!model.hasSourceMetadata)
                        .help(model.hasSourceMetadata
                              ? "Carry the source file's EXIF/GPS/IPTC into the export"
                              : "This image has no metadata to keep")
                }

                Button("Reset All") { model.reset() }
                    .disabled(model.adjustments.isNeutral)
                    .frame(maxWidth: .infinity)
            }
            .padding(14)
            // Disable only the controls, not the ScrollView, so scrolling still
            // works before an image is loaded.
            .disabled(!model.hasImage)
        }
        .frame(width: 230)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func pickerRow<Content: View>(_ title: String, @ViewBuilder _ picker: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium))
            Spacer()
            picker()
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
