import AppKit
import CoreGraphics

@MainActor
public protocol SelectionServicing {
    func selectRectangle() async throws -> CaptureSelection
}

public enum SelectionError: LocalizedError, Equatable {
    case cancelled
    case noScreenAvailable
    case selectionTooSmall

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Selection was cancelled."
        case .noScreenAvailable:
            return "No screen is available for selection."
        case .selectionTooSmall:
            return "The selected region is too small."
        }
    }
}

public final class AppKitSelectionService: SelectionServicing {
    private let windowVisibilityController: CaptureWindowVisibilityControlling
    private let screenProvider: @MainActor () -> [NSScreen]

    public init(windowVisibilityController: CaptureWindowVisibilityControlling = AppKitCaptureWindowVisibilityController()) {
        self.windowVisibilityController = windowVisibilityController
        self.screenProvider = { NSScreen.screens }
    }

    init(
        windowVisibilityController: CaptureWindowVisibilityControlling = AppKitCaptureWindowVisibilityController(),
        screenProvider: @escaping @MainActor () -> [NSScreen]
    ) {
        self.windowVisibilityController = windowVisibilityController
        self.screenProvider = screenProvider
    }

    public func selectRectangle() async throws -> CaptureSelection {
        let screens = screenProvider()
        guard !screens.isEmpty else {
            throw SelectionError.noScreenAvailable
        }

        return try await SelectionOverlaySession(
            screens: screens,
            windowVisibilityController: windowVisibilityController
        ).select()
    }
}

@MainActor
private final class SelectionOverlaySession {
    private let screens: [NSScreen]
    private let windowVisibilityController: CaptureWindowVisibilityControlling
    private var windows: [NSWindow] = []
    private var keyEventMonitor: Any?
    private var continuation: CheckedContinuation<CaptureSelection, Error>?

    init(screens: [NSScreen], windowVisibilityController: CaptureWindowVisibilityControlling) {
        self.screens = screens
        self.windowVisibilityController = windowVisibilityController
    }

    func select() async throws -> CaptureSelection {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard SelectionOverlayKeyboardPolicy.isCancelEvent(event) else {
                    return event
                }

                self?.finish(.failure(SelectionError.cancelled))
                return nil
            }

            let windowFrames = SelectionOverlayGeometry.overlayWindowFrames(forScreenFrames: screens.map(\.frame))
            let windows = zip(screens, windowFrames).map { screen, windowFrame in
                let view = SelectionOverlayView(screen: screen) { [weak self] result in
                    self?.finish(result)
                }
                let window = SelectionOverlayWindow(
                    contentRect: windowFrame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false,
                    screen: screen
                )
                window.cancelHandler = { [weak self] in
                    self?.finish(.failure(SelectionError.cancelled))
                }
                window.level = .screenSaver
                window.isOpaque = false
                window.acceptsMouseMovedEvents = true
                window.backgroundColor = .clear
                window.ignoresMouseEvents = false
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                window.contentView = view
                return window
            }

            self.windows = windows
            NSApp.activate(ignoringOtherApps: true)
            windows.forEach { $0.orderFrontRegardless() }
            windows.first?.makeKeyAndOrderFront(nil)
            windowVisibilityController.hideCaptureWindows(excluding: windows.first)
        }
    }

    private func finish(_ result: Result<CaptureSelection, Error>) {
        guard let continuation else {
            return
        }

        SelectionOverlayCursor.restoreDefaultCursor()
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        switch result {
        case .success(let selection):
            continuation.resume(returning: selection)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
        self.continuation = nil
    }
}

enum SelectionOverlayKeyboardPolicy {
    static let escapeKeyCode: UInt16 = 53

    static func isCancelEvent(_ event: NSEvent) -> Bool {
        event.type == .keyDown
            && (event.keyCode == escapeKeyCode || event.charactersIgnoringModifiers == "\u{1b}")
    }
}

enum SelectionOverlayGeometry {
    static func viewFrame(forScreenFrame screenFrame: CGRect) -> CGRect {
        CGRect(origin: .zero, size: screenFrame.size)
    }

    static func overlayWindowFrames(forScreenFrames screenFrames: [CGRect]) -> [CGRect] {
        screenFrames
    }

    static func globalSelectionRect(localRect: CGRect, screenFrame: CGRect) -> CGRect {
        localRect.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
    }
}

private final class SelectionOverlayWindow: NSWindow {
    var cancelHandler: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard SelectionOverlayKeyboardPolicy.isCancelEvent(event) else {
            super.keyDown(with: event)
            return
        }

        cancelHandler?()
    }

    override func cancelOperation(_ sender: Any?) {
        cancelHandler?()
    }
}

@MainActor
enum SelectionOverlayCursor {
    static let cursor: NSCursor = makePlusCursor()
    static let defaultCursor: NSCursor = .arrow
    static let reassertionInterval: TimeInterval = 1.0 / 30.0
    private static var isSelectionCursorPushed = false
    private static var isNativeCursorHidden = false
    static var isSelectionCursorActive: Bool {
        isSelectionCursorPushed
    }
    static var isNativeCursorHiddenForSelection: Bool {
        isNativeCursorHidden
    }

    static func applySelectionCursor() {
        cursor.set()
    }

    static func pushSelectionCursor() {
        guard !isSelectionCursorPushed else {
            applySelectionCursor()
            return
        }

        cursor.push()
        isSelectionCursorPushed = true
    }

    static func reassertSelectionCursor() {
        guard isSelectionCursorPushed else {
            pushSelectionCursor()
            return
        }

        applySelectionCursor()
    }

    static func hideNativeCursorForSelection() {
        guard !isNativeCursorHidden else {
            return
        }

        NSCursor.hide()
        isNativeCursorHidden = true
    }

    static func restoreDefaultCursor() {
        if isSelectionCursorPushed {
            NSCursor.pop()
            isSelectionCursorPushed = false
        }
        if isNativeCursorHidden {
            NSCursor.unhide()
            isNativeCursorHidden = false
        }
        defaultCursor.set()
    }

    private static func makePlusCursor() -> NSCursor {
        let size = NSSize(width: 33, height: 33)
        let hotSpot = NSPoint(x: 16, y: 16)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: 8, y: 16))
        path.line(to: NSPoint(x: 25, y: 16))
        path.move(to: NSPoint(x: 16, y: 8))
        path.line(to: NSPoint(x: 16, y: 25))

        NSColor.black.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 5
        path.stroke()

        NSColor.white.setStroke()
        path.lineWidth = 2.4
        path.stroke()
        image.unlockFocus()
        image.isTemplate = false

        return NSCursor(image: image, hotSpot: hotSpot)
    }
}

struct SelectionOverlayReticleSegment {
    let start: CGPoint
    let end: CGPoint
}

enum SelectionOverlayReticle {
    static let radius: CGFloat = 13
    static let strokeWidth: CGFloat = 2.25
    private static let outlineWidth: CGFloat = 5

    static func lineSegments(centeredAt center: CGPoint) -> [SelectionOverlayReticleSegment] {
        [
            SelectionOverlayReticleSegment(
                start: CGPoint(x: center.x - radius, y: center.y),
                end: CGPoint(x: center.x + radius, y: center.y)
            ),
            SelectionOverlayReticleSegment(
                start: CGPoint(x: center.x, y: center.y - radius),
                end: CGPoint(x: center.x, y: center.y + radius)
            )
        ]
    }

    static func draw(centeredAt center: CGPoint) {
        let path = NSBezierPath()
        path.lineCapStyle = .round
        for segment in lineSegments(centeredAt: center) {
            path.move(to: segment.start)
            path.line(to: segment.end)
        }

        NSColor.black.withAlphaComponent(0.72).setStroke()
        path.lineWidth = outlineWidth
        path.stroke()

        NSColor.white.setStroke()
        path.lineWidth = strokeWidth
        path.stroke()
    }
}

private final class SelectionOverlayView: NSView {
    private let screen: NSScreen
    private let completion: (Result<CaptureSelection, Error>) -> Void
    private var acceptsSelectionEvents = false
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var cursorPoint: CGPoint?
    private var cursorReassertionTimer: Timer?

    init(screen: NSScreen, completion: @escaping (Result<CaptureSelection, Error>) -> Void) {
        self.screen = screen
        self.completion = completion
        super.init(frame: SelectionOverlayGeometry.viewFrame(forScreenFrame: screen.frame))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.acceptsSelectionEvents = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        guard let window else {
            stopCursorReassertionTimer()
            return
        }

        window.makeFirstResponder(self)
        window.invalidateCursorRects(for: self)
        SelectionOverlayCursor.pushSelectionCursor()
        SelectionOverlayCursor.hideNativeCursorForSelection()
        updateCursorPoint(from: window.mouseLocationOutsideOfEventStream)
        startCursorReassertionTimer()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: SelectionOverlayCursor.cursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        SelectionOverlayCursor.reassertSelectionCursor()
        updateCursorPoint(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        SelectionOverlayCursor.reassertSelectionCursor()
        updateCursorPoint(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        SelectionOverlayCursor.reassertSelectionCursor()
        updateCursorPoint(with: event)
        guard acceptsSelectionEvents else {
            return
        }

        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        SelectionOverlayCursor.reassertSelectionCursor()
        updateCursorPoint(with: event)
        guard acceptsSelectionEvents else {
            return
        }

        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        SelectionOverlayCursor.reassertSelectionCursor()
        updateCursorPoint(with: event)
        guard acceptsSelectionEvents else {
            return
        }

        currentPoint = convert(event.locationInWindow, from: nil)
        guard let selection = currentSelection else {
            complete(.failure(SelectionError.cancelled))
            return
        }

        if selection.isUsable {
            complete(.success(selection))
        } else {
            complete(.failure(SelectionError.selectionTooSmall))
        }
    }

    override func keyDown(with event: NSEvent) {
        guard SelectionOverlayKeyboardPolicy.isCancelEvent(event) else {
            super.keyDown(with: event)
            return
        }

        cancelSelection()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if let rect = currentLocalSelectionRect {
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            path.stroke()
        }

        if let cursorPoint {
            SelectionOverlayReticle.draw(centeredAt: cursorPoint)
        }
    }

    private func updateCursorPoint(with event: NSEvent) {
        updateCursorPoint(from: convert(event.locationInWindow, from: nil))
    }

    private func updateCursorPoint(from point: CGPoint) {
        cursorPoint = point
        needsDisplay = true
    }

    private var currentLocalSelectionRect: CGRect? {
        guard let startPoint, let currentPoint else {
            return nil
        }

        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    private var currentSelection: CaptureSelection? {
        guard let localRect = currentLocalSelectionRect else {
            return nil
        }

        let globalRect = SelectionOverlayGeometry.globalSelectionRect(localRect: localRect, screenFrame: screen.frame)
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
        return CaptureSelection(
            displayID: displayID,
            screenFrame: screen.frame,
            rect: globalRect,
            scale: screen.backingScaleFactor
        )
    }

    private func startCursorReassertionTimer() {
        stopCursorReassertionTimer()
        let timer = Timer(timeInterval: SelectionOverlayCursor.reassertionInterval, repeats: true) { _ in
            Task { @MainActor in
                SelectionOverlayCursor.reassertSelectionCursor()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        cursorReassertionTimer = timer
    }

    private func stopCursorReassertionTimer() {
        cursorReassertionTimer?.invalidate()
        cursorReassertionTimer = nil
    }

    func cancelSelection() {
        complete(.failure(SelectionError.cancelled))
    }

    private func complete(_ result: Result<CaptureSelection, Error>) {
        stopCursorReassertionTimer()
        SelectionOverlayCursor.restoreDefaultCursor()
        completion(result)
    }
}
