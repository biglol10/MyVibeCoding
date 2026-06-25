import AppKit

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    var onOpenMainWindow: (() -> Void)?
    var onToggleWidget: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "MyMacCalendar")

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Calendar", action: #selector(openMainWindow), keyEquivalent: "")
        let widgetItem = NSMenuItem(title: "Show or Hide Widget", action: #selector(toggleWidget), keyEquivalent: "")
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        [openItem, widgetItem, settingsItem].forEach { $0.target = self }
        quitItem.target = NSApp

        menu.addItem(openItem)
        menu.addItem(widgetItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    @objc private func openMainWindow() {
        onOpenMainWindow?()
    }

    @objc private func toggleWidget() {
        onToggleWidget?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }
}
