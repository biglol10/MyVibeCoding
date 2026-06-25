import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController.onOpenMainWindow = {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        menuBarController.onToggleWidget = { [weak self] in
            self?.toggleWidget()
        }
        menuBarController.onOpenSettings = {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        menuBarController.install()
    }

    private func toggleWidget() {
        WidgetCoordinator.shared.toggleVisibility()
    }
}
