import AppKit

@MainActor
final class AppKitSettingsWindowPresenter {
    static var shared: AppKitSettingsWindowPresenter {
        AppKitSettingsWindowPresenter(
            windowProvider: { NSApp.windows },
            activateApplication: { NSApp.activate(ignoringOtherApps: true) },
            showSettingsFallback: {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
            schedule: { action in
                Task { @MainActor in
                    await Task.yield()
                    action()
                }
            }
        )
    }

    private let windowProvider: @MainActor () -> [NSWindow]
    private let activateApplication: @MainActor () -> Void
    private let showSettingsFallback: @MainActor () -> Void
    private let schedule: @MainActor (@escaping @MainActor () -> Void) -> Void

    init(
        windowProvider: @escaping @MainActor () -> [NSWindow],
        activateApplication: @escaping @MainActor () -> Void,
        showSettingsFallback: @escaping @MainActor () -> Void,
        schedule: @escaping @MainActor (@escaping @MainActor () -> Void) -> Void
    ) {
        self.windowProvider = windowProvider
        self.activateApplication = activateApplication
        self.showSettingsFallback = showSettingsFallback
        self.schedule = schedule
    }

    func present(openSettings: () -> Void) {
        SettingsTab.selectDefaultOpenTab()
        openSettings()
        activateApplication()
        schedule { [weak self] in
            self?.raiseSettingsWindow()
        }
    }

    func presentUsingApplicationAction() {
        present(openSettings: {})
    }

    private func raiseSettingsWindow() {
        activateApplication()
        guard let window = windowProvider().first(where: Self.isSettingsWindow) else {
            showSettingsFallback()
            return
        }

        window.makeKeyAndOrderFront(nil)
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        if window.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" {
            return true
        }

        return SettingsTab.allCases.contains { $0.title == window.title }
    }
}
