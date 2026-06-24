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
        }
        .defaultSize(width: 560, height: 128)
        .commands {
            CommandMenu("Capture") {
                Button("Capture") {
                    startScreenshotCapture()
                }
                .keyboardShortcut(
                    shortcutBinding(for: .newScreenshot).keyEquivalent,
                    modifiers: shortcutBinding(for: .newScreenshot).eventModifiers
                )

                Button("Record") {
                    startScreenRecording()
                }
                .keyboardShortcut(
                    shortcutBinding(for: .newRecording).keyEquivalent,
                    modifiers: shortcutBinding(for: .newRecording).eventModifiers
                )

                Divider()

                OpenSettingsCommand(
                    binding: shortcutBinding(for: .openSettings)
                )
            }

            CommandGroup(replacing: .help) {
                Button("CaptureStudio Guide") {
                    appState.isGuidePresented = true
                }
                .keyboardShortcut("?", modifiers: [.command])
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

    private func startScreenshotCapture() {
        Task { @MainActor in
            await CaptureCoordinator(
                appState: appState,
                settingsStore: settingsStore
            ).startScreenshotCapture()
        }
    }

    private func startScreenRecording() {
        Task { @MainActor in
            await CaptureCoordinator(
                appState: appState,
                settingsStore: settingsStore
            ).startScreenRecording()
        }
    }

}

private struct OpenSettingsCommand: View {
    @Environment(\.openSettings) private var openSettings
    let binding: ShortcutBinding

    var body: some View {
        Button("Settings") {
            SettingsTab.selectDefaultOpenTab()
            openSettings()
        }
        .keyboardShortcut(binding.keyEquivalent, modifiers: binding.eventModifiers)
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
