import SwiftUI

@main
struct CaptureStudioApp: App {
    @StateObject private var appState: AppState
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var shortcutManager = ShortcutManager()
    @StateObject private var globalShortcutController = GlobalShortcutController()
    @StateObject private var captureCoordinator: CaptureCoordinator

    init() {
        let appState = AppState()
        let settingsStore = SettingsStore()
        _appState = StateObject(wrappedValue: appState)
        _settingsStore = StateObject(wrappedValue: settingsStore)
        _captureCoordinator = StateObject(
            wrappedValue: CaptureCoordinator(
                appState: appState,
                settingsStore: settingsStore
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            MainWindowContainer(
                appState: appState,
                settingsStore: settingsStore,
                captureCoordinator: captureCoordinator
            )
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

                Button("Record") {
                    startScreenRecording()
                }

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
            await captureCoordinator.startScreenshotCapture()
        }
    }

    private func startScreenRecording() {
        Task { @MainActor in
            await captureCoordinator.startScreenRecording()
        }
    }

    private func stopActiveRecording() {
        Task { @MainActor in
            await captureCoordinator.stopActiveRecording()
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
    @ObservedObject private var appState: AppState
    @ObservedObject private var settingsStore: SettingsStore
    @StateObject private var captureCoordinator: CaptureCoordinator

    init(
        appState: AppState,
        settingsStore: SettingsStore,
        captureCoordinator: CaptureCoordinator
    ) {
        self.appState = appState
        self.settingsStore = settingsStore
        _captureCoordinator = StateObject(wrappedValue: captureCoordinator)
    }

    var body: some View {
        MainWindowView(
            captureCoordinator: captureCoordinator,
            appState: appState
        )
    }
}
