import SwiftUI

@main
struct MyMacSearchApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            SearchRootView(model: model)
                .frame(minWidth: 920, minHeight: 560)
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Search") {
                Button("Focus Search") {
                    model.activateSearchWindow()
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("Clear Search") {
                    model.clearSearch()
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            CommandMenu("Result") {
                Button("Open") { model.perform(.open) }
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(model.selectedEntry == nil)
                Button("Quick Look") { model.toggleQuickLook() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(model.selectedEntry == nil)
                Divider()
                Button("Reveal in Finder") { model.perform(.revealInFinder) }
                    .disabled(model.selectedEntry == nil)
                Button("Copy Path") { model.perform(.copyPath) }
                    .keyboardShortcut("c", modifiers: [.command])
                    .disabled(model.selectedEntry == nil)
                Button("Open in Terminal") { model.perform(.openInTerminal) }
                    .disabled(model.selectedEntry == nil)
                Button("Open in MyMacFinder") { model.perform(.openInMyMacFinder) }
                    .disabled(model.selectedEntry == nil)
            }
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 620, height: 520)
        }

        Window("Index Center", id: "index-center") {
            IndexCenterView(model: model)
                .frame(minWidth: 780, minHeight: 520)
        }
        .defaultSize(width: 900, height: 620)
    }
}
