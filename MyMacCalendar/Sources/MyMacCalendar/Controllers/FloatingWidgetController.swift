import AppKit
import SwiftUI
import MyMacCalendarCore

@MainActor
final class FloatingWidgetController {
    private var window: NSWindow?
    private var detailWindow: NSWindow?
    private var listWindow: NSWindow?
    private var hostingController: NSHostingController<FloatingWidgetView>?
    private var latestOccurrences: [EventOccurrence] = []
    private var latestOnSelect: ((EventOccurrence) -> Void)?

    func show(occurrences: [EventOccurrence], opacity: Double, alwaysOnTop: Bool, onSelect: @escaping (EventOccurrence) -> Void) {
        latestOccurrences = occurrences
        latestOnSelect = onSelect
        let onShowAll: () -> Void = { [weak self] in
            guard let self,
                  let latestOnSelect = self.latestOnSelect else { return }
            self.showAll(occurrences: self.latestOccurrences, onSelect: latestOnSelect)
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
        refreshOpenListWindow()
        window?.level = alwaysOnTop ? .floating : .normal
        window?.alphaValue = opacity
        showWithoutActivating()
    }

    func showDetail(_ detail: EventOccurrenceDetail) {
        if detailWindow == nil {
            let hosting = NSHostingController(rootView: FloatingEventDetailView(detail: detail))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "일정 상세"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.setFrame(NSRect(x: 380, y: 600, width: 320, height: 260), display: true)
            detailWindow = newWindow
        } else {
            (detailWindow?.contentViewController as? NSHostingController<FloatingEventDetailView>)?.rootView =
                FloatingEventDetailView(detail: detail)
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

    private func refreshOpenListWindow() {
        guard listWindow?.isVisible == true,
              let latestOnSelect else { return }
        (listWindow?.contentViewController as? NSHostingController<FloatingWidgetAllEventsView>)?.rootView =
            FloatingWidgetAllEventsView(occurrences: latestOccurrences, onSelect: latestOnSelect)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func showWithoutActivating() {
        window?.orderFront(nil)
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
            return defaultFrame()
        }

        let frame = NSRect(
            x: defaults.double(forKey: originXKey),
            y: defaults.double(forKey: originYKey),
            width: FloatingWidgetLayout.size.width,
            height: FloatingWidgetLayout.size.height
        )
        return validatedFrame(frame)
    }

    static func saveFrame(_ frame: NSRect) {
        UserDefaults.standard.set(frame.origin.x, forKey: originXKey)
        UserDefaults.standard.set(frame.origin.y, forKey: originYKey)
    }

    private static func validatedFrame(_ frame: NSRect) -> NSRect {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        guard visibleFrames.isEmpty == false else {
            return FloatingWidgetLayout.initialFrame
        }
        guard visibleFrames.contains(where: { $0.intersects(frame) }) else {
            return defaultFrame()
        }
        return frame
    }

    private static func defaultFrame() -> NSRect {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return FloatingWidgetLayout.initialFrame
        }

        let maxX = max(visibleFrame.minX, visibleFrame.maxX - FloatingWidgetLayout.size.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - FloatingWidgetLayout.size.height)
        let x = min(max(FloatingWidgetLayout.initialFrame.origin.x, visibleFrame.minX), maxX)
        let y = min(max(FloatingWidgetLayout.initialFrame.origin.y, visibleFrame.minY), maxY)
        return NSRect(
            x: x,
            y: y,
            width: FloatingWidgetLayout.size.width,
            height: FloatingWidgetLayout.size.height
        )
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
