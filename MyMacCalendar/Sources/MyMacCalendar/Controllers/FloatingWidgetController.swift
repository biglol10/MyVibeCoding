import AppKit
import SwiftUI
import MyMacCalendarCore

@MainActor
final class FloatingWidgetController {
    private var window: NSWindow?
    private var hostingController: NSHostingController<FloatingWidgetView>?

    func show(occurrences: [EventOccurrence], opacity: Double, alwaysOnTop: Bool) {
        if window == nil {
            let hosting = NSHostingController(rootView: FloatingWidgetView(occurrences: occurrences))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.styleMask = [.borderless]
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newWindow.setFrame(NSRect(x: 80, y: 600, width: 280, height: 260), display: true)
            newWindow.isReleasedWhenClosed = false
            window = newWindow
            hostingController = hosting
        }

        hostingController?.rootView = FloatingWidgetView(occurrences: occurrences)
        window?.level = alwaysOnTop ? .floating : .normal
        window?.alphaValue = opacity
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }
}
