import AppKit
import MyMacCalendarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = MenuBarController()
    private var settingsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController.onOpenMainWindow = { [weak self] in
            self?.openMainWindow()
        }
        menuBarController.onQuickAdd = { [weak self] in
            self?.openMainWindow()
            NotificationCenter.default.post(name: .openQuickAddSheet, object: nil)
        }
        menuBarController.onToggleWidget = { [weak self] in
            self?.toggleWidget()
        }
        menuBarController.onOpenSettings = { [weak self] in
            self?.openMainWindow()
            NotificationCenter.default.post(name: .openSettingsSheet, object: nil)
        }
        menuBarController.install()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .appSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let showMenuBar = notification.userInfo?["showMenuBar"] as? Bool
            Task { @MainActor [weak self] in
                guard let showMenuBar else { return }
                self?.menuBarController.setVisible(showMenuBar)
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.openMainWindowIfNeeded()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return false
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if bringExistingMainWindowToFront() {
            return
        }

        NSApp.sendAction(Selector(("newWindow:")), to: nil, from: nil)
        DispatchQueue.main.async { [weak self] in
            _ = self?.bringExistingMainWindowToFront()
        }
    }

    private func openMainWindowIfNeeded() {
        let hasVisibleMainWindow = NSApp.windows.contains { window in
            window.title == AppVersion.name && window.isVisible
        }
        if NSApp.windows.isEmpty || hasVisibleMainWindow == false {
            openMainWindow()
        }
    }

    @discardableResult
    private func bringExistingMainWindowToFront() -> Bool {
        if let mainWindow = NSApp.windows.first(where: { window in
            window.title == AppVersion.name
        }) {
            mainWindow.makeKeyAndOrderFront(nil)
            return true
        }
        return false
    }

    private func toggleWidget() {
        WidgetCoordinator.shared.toggleVisibility()
    }
}
