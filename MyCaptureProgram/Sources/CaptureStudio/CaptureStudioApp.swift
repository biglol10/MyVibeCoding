import SwiftUI

@main
struct CaptureStudioApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var shortcutManager = ShortcutManager()
    @StateObject private var globalShortcutController = GlobalShortcutController()

    var body: some Scene {
        WindowGroup {
            MainWindowContainer()
                .environmentObject(appState)
                .environmentObject(settingsStore)
                .environmentObject(shortcutManager)
                .onAppear {
                    globalShortcutController.configure(shortcutManager: shortcutManager, actionHandler: handleShortcutAction)
                }
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

                Button("Stop Recording") {
                    stopActiveRecording()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(!appState.isRecordingInProgress)

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
                .frame(width: 760, height: 580)
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

    private func stopActiveRecording() {
        Task { @MainActor in
            await CaptureCoordinator(
                appState: appState,
                settingsStore: settingsStore
            ).stopActiveRecording()
        }
    }

    private func handleShortcutAction(_ action: ShortcutAction) {
        switch action {
        case .newScreenshot:
            startScreenshotCapture()
        case .newRecording:
            startScreenRecording()
        case .openSettings:
            SettingsTab.selectDefaultOpenTab()
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .textExtraction, .colorPicker, .lastCapture:
            break
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
