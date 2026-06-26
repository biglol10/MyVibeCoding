import AppKit

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    var onOpenMainWindow: (() -> Void)?
    var onQuickAdd: (() -> Void)?
    var onToggleWidget: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    func install() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "MyMacCalendar")

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "캘린더 열기", action: #selector(openMainWindow), keyEquivalent: "")
        let quickAddItem = NSMenuItem(title: "빠른 추가", action: #selector(openQuickAdd), keyEquivalent: "n")
        let widgetItem = NSMenuItem(title: "위젯 보이기/숨기기", action: #selector(toggleWidget), keyEquivalent: "")
        let settingsItem = NSMenuItem(title: "설정", action: #selector(openSettings), keyEquivalent: ",")
        let quitItem = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        [openItem, quickAddItem, widgetItem, settingsItem].forEach { $0.target = self }
        quitItem.target = NSApp

        menu.addItem(openItem)
        menu.addItem(quickAddItem)
        menu.addItem(widgetItem)
        menu.addItem(.separator())
        menu.addItem(settingsItem)
        menu.addItem(quitItem)
        statusItem?.menu = menu
    }

    @objc private func openMainWindow() {
        onOpenMainWindow?()
    }

    @objc private func openQuickAdd() {
        onQuickAdd?()
    }

    @objc private func toggleWidget() {
        onToggleWidget?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }
}
