import SwiftUI

@main
struct CaptureStudioApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var shortcutManager = ShortcutManager()

    var body: some Scene {
        WindowGroup {
            MainWindowContainer()
                .environmentObject(appState)
                .environmentObject(settingsStore)
                .environmentObject(shortcutManager)
                .frame(minWidth: 620, minHeight: 430)
        }
        .commands {
            CommandMenu("Capture") {
                Button("New Screenshot") {
                    startCapture(mode: .screenshot)
                }
                .keyboardShortcut(
                    shortcutBinding(for: .newScreenshot).keyEquivalent,
                    modifiers: shortcutBinding(for: .newScreenshot).eventModifiers
                )

                Button("New Recording") {
                    startCapture(mode: .record)
                }
                .keyboardShortcut(
                    shortcutBinding(for: .newRecording).keyEquivalent,
                    modifiers: shortcutBinding(for: .newRecording).eventModifiers
                )

                Divider()

                Button("Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(
                    shortcutBinding(for: .openSettings).keyEquivalent,
                    modifiers: shortcutBinding(for: .openSettings).eventModifiers
                )
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settingsStore)
                .environmentObject(shortcutManager)
                .frame(width: 640, height: 520)
        }
    }

    private func shortcutBinding(for action: ShortcutAction) -> ShortcutBinding {
        shortcutManager.bindings[action] ?? ShortcutDefinition.defaultBinding(for: action)
    }

    private func startCapture(mode: CaptureMode) {
        Task { @MainActor in
            appState.captureMode = mode
            await CaptureCoordinator(
                appState: appState,
                settingsStore: settingsStore
            ).startNewCapture()
        }
    }
}

private struct MainWindowContainer: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        MainWindowView(
            captureCoordinator: CaptureCoordinator(
                appState: appState,
                settingsStore: settingsStore
            ),
            appState: appState
        )
    }
}
