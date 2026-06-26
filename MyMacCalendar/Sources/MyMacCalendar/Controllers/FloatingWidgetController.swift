import AppKit
import SwiftUI
import MyMacCalendarCore

@MainActor
final class FloatingWidgetController {
    private var window: NSWindow?
    private var detailWindow: NSWindow?
    private var listWindow: NSWindow?
    private var hostingController: NSHostingController<FloatingWidgetView>?

    func show(occurrences: [EventOccurrence], opacity: Double, alwaysOnTop: Bool, onSelect: @escaping (EventOccurrence) -> Void) {
        let onShowAll: () -> Void = { [weak self] in
            guard let self else { return }
            self.showAll(occurrences: occurrences, onSelect: onSelect)
        }

        if window == nil {
            let hosting = FloatingWidgetHostingController(
                rootView: FloatingWidgetView(occurrences: occurrences, onSelect: onSelect, onShowAll: onShowAll)
            )
            let newWindow = FloatingWidgetWindow(contentViewController: hosting)
            newWindow.styleMask = [.borderless]
            newWindow.styleMask.remove(.resizable)
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.isMovableByWindowBackground = true
            newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            newWindow.minSize = FloatingWidgetLayout.size
            newWindow.maxSize = FloatingWidgetLayout.size
            newWindow.contentMinSize = FloatingWidgetLayout.size
            newWindow.contentMaxSize = FloatingWidgetLayout.size
            newWindow.setFrame(FloatingWidgetPositionStore.loadFrame(), display: true)
            newWindow.setContentSize(FloatingWidgetLayout.size)
            newWindow.isReleasedWhenClosed = false
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(floatingWidgetDidMove(_:)),
                name: NSWindow.didMoveNotification,
                object: newWindow
            )
            window = newWindow
            hostingController = hosting
        }

        hostingController?.rootView = FloatingWidgetView(occurrences: occurrences, onSelect: onSelect, onShowAll: onShowAll)
        window?.level = alwaysOnTop ? .floating : .normal
        window?.alphaValue = opacity
        window?.makeKeyAndOrderFront(nil)
    }

    func showDetail(for event: CalendarEvent) {
        if detailWindow == nil {
            let hosting = NSHostingController(rootView: FloatingEventDetailView(event: event))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "일정 상세"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.setFrame(NSRect(x: 380, y: 600, width: 320, height: 260), display: true)
            detailWindow = newWindow
        } else {
            (detailWindow?.contentViewController as? NSHostingController<FloatingEventDetailView>)?.rootView = FloatingEventDetailView(event: event)
        }

        detailWindow?.level = .floating
        detailWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showAll(occurrences: [EventOccurrence], onSelect: @escaping (EventOccurrence) -> Void) {
        if listWindow == nil {
            let hosting = NSHostingController(rootView: FloatingWidgetAllEventsView(occurrences: occurrences, onSelect: onSelect))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "다가오는 일정"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.setFrame(NSRect(x: 360, y: 520, width: 340, height: 380), display: true)
            listWindow = newWindow
        } else {
            (listWindow?.contentViewController as? NSHostingController<FloatingWidgetAllEventsView>)?.rootView =
                FloatingWidgetAllEventsView(occurrences: occurrences, onSelect: onSelect)
        }

        listWindow?.level = .floating
        listWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    @objc private func floatingWidgetDidMove(_ notification: Notification) {
        guard let movedWindow = notification.object as? NSWindow else { return }
        FloatingWidgetPositionStore.saveFrame(movedWindow.frame)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

private enum FloatingWidgetLayout {
    static let size = NSSize(width: 260, height: 260)
    static let initialFrame = NSRect(x: 80, y: 600, width: size.width, height: size.height)
}

private enum FloatingWidgetPositionStore {
    private static let originXKey = "floatingWidget.origin.x"
    private static let originYKey = "floatingWidget.origin.y"

    static func loadFrame() -> NSRect {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: originXKey) != nil,
              defaults.object(forKey: originYKey) != nil else {
            return FloatingWidgetLayout.initialFrame
        }

        return NSRect(
            x: defaults.double(forKey: originXKey),
            y: defaults.double(forKey: originYKey),
            width: FloatingWidgetLayout.size.width,
            height: FloatingWidgetLayout.size.height
        )
    }

    static func saveFrame(_ frame: NSRect) {
        UserDefaults.standard.set(frame.origin.x, forKey: originXKey)
        UserDefaults.standard.set(frame.origin.y, forKey: originYKey)
    }
}

private final class FloatingWidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let location = event.locationInWindow
            let isHeaderDrag = location.y >= frame.height - FloatingWidgetLayout.dragHandleHeight
            if isHeaderDrag {
                performDrag(with: event)
                return
            }
        }

        super.sendEvent(event)
    }
}

private final class FloatingWidgetHostingController: NSHostingController<FloatingWidgetView> {
    override func loadView() {
        view = FloatingWidgetHostingView(rootView: rootView)
    }
}

private final class FloatingWidgetHostingView: NSHostingView<FloatingWidgetView> {
    override var mouseDownCanMoveWindow: Bool { true }
}

private extension FloatingWidgetLayout {
    static let dragHandleHeight: CGFloat = 42
}
