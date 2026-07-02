import SwiftUI
import AppKit

/// Receives open-file events. `.onOpenURL` alone misses files delivered at
/// process launch (the event can arrive before the SwiftUI view attaches),
/// so document opens route through the classic delegate instead.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        EditorModel.shared.load(url: url)
    }
}

@main
struct PicoloApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = EditorModel.shared

    var body: some Scene {
        Window("Picolo", id: "main") {
            HStack(spacing: 0) {
                ImageCanvas(model: model)
                    .frame(minWidth: 360, minHeight: 320)
                Divider()
                AdjustmentsPanel(model: model)
            }
            .frame(minWidth: 620, minHeight: 420)
            .alert("Something went wrong", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .commands {
            // File
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.open() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { model.save() }
                    .keyboardShortcut("s")
                    .disabled(!model.hasImage)
                Button("Save As…") { model.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(!model.hasImage)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { model.undo() }
                    .keyboardShortcut("z")
                    .disabled(!model.canUndo)
                Button("Redo") { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo)
            }
            // View — zoom
            CommandGroup(before: .toolbar) {
                Button("Zoom In") { model.zoomIn() }
                    .keyboardShortcut("+")
                    .disabled(!model.hasImage)
                Button("Zoom Out") { model.zoomOut() }
                    .keyboardShortcut("-")
                    .disabled(!model.hasImage)
                Button("Zoom to Fit") { model.zoomToFit() }
                    .keyboardShortcut("0")
                    .disabled(!model.hasImage)
                Button("Actual Size") { model.zoomToActualSize() }
                    .keyboardShortcut("1")
                    .disabled(!model.hasImage)
                Divider()
            }
            // Image — geometry
            CommandMenu("Image") {
                Button("Crop…") { model.beginCrop() }
                    .keyboardShortcut("k")
                    .disabled(!model.hasImage || model.isCropping)
                Divider()
                Button("Rotate Left") { model.rotateLeft() }
                    .keyboardShortcut("[")
                    .disabled(!model.hasImage)
                Button("Rotate Right") { model.rotateRight() }
                    .keyboardShortcut("]")
                    .disabled(!model.hasImage)
                Divider()
                Button("Flip Horizontal") { model.flipHorizontal() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                    .disabled(!model.hasImage)
                Button("Flip Vertical") { model.flipVertical() }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                    .disabled(!model.hasImage)
            }
            // Edit — paste/copy of the whole image
            CommandGroup(replacing: .pasteboard) {
                Button("Copy Image") { model.copy() }
                    .keyboardShortcut("c")
                    .disabled(!model.hasImage)
                Button("Paste Image") { model.paste() }
                    .keyboardShortcut("v")
                Divider()
                Button("Reset Adjustments") { model.reset() }
                    .keyboardShortcut("r")
                    .disabled(!model.hasImage)
            }
        }
    }
}
