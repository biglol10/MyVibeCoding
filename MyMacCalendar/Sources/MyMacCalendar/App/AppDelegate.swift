import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = MenuBarController()

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
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return false
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow = NSApp.windows.first(where: { window in
            window.title == "MyMacCalendar"
        }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    private func toggleWidget() {
        WidgetCoordinator.shared.toggleVisibility()
    }
}
