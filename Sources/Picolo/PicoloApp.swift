import SwiftUI

@main
struct PicoloApp: App {
    @StateObject private var model = EditorModel()

    var body: some Scene {
        Window("Picolo", id: "main") {
            HStack(spacing: 0) {
                ImageCanvas(model: model)
                    .frame(minWidth: 360, minHeight: 320)
                Divider()
                AdjustmentsPanel(model: model)
            }
            .frame(minWidth: 620, minHeight: 420)
            .onOpenURL { url in model.load(url: url) }
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
