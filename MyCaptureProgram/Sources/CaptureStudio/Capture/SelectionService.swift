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
    public init() {}

    public func selectRectangle() async throws -> CaptureSelection {
        guard let screen = NSScreen.main else {
            throw SelectionError.noScreenAvailable
        }

        return try await SelectionOverlaySession(screen: screen).select()
    }
}

@MainActor
private final class SelectionOverlaySession {
    private let screen: NSScreen
    private var window: NSWindow?
    private var continuation: CheckedContinuation<CaptureSelection, Error>?

    init(screen: NSScreen) {
        self.screen = screen
    }

    func select() async throws -> CaptureSelection {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let view = SelectionOverlayView(screen: screen) { [weak self] result in
                self?.finish(result)
            }
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.window = window
        }
    }

    private func finish(_ result: Result<CaptureSelection, Error>) {
        window?.orderOut(nil)
        window = nil
        switch result {
        case .success(let selection):
            continuation?.resume(returning: selection)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}

private final class SelectionOverlayView: NSView {
    private let screen: NSScreen
    private let completion: (Result<CaptureSelection, Error>) -> Void
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    init(screen: NSScreen, completion: @escaping (Result<CaptureSelection, Error>) -> Void) {
        self.screen = screen
        self.completion = completion
        super.init(frame: screen.frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let selection = currentSelection else {
            completion(.failure(SelectionError.cancelled))
            return
        }

        if selection.isUsable {
            completion(.success(selection))
        } else {
            completion(.failure(SelectionError.selectionTooSmall))
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            completion(.failure(SelectionError.cancelled))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let rect = currentSelection?.rect else {
            return
        }

        NSColor.clear.setFill()
        rect.fill(using: .copy)
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()
    }

    private var currentSelection: CaptureSelection? {
        guard let startPoint, let currentPoint else {
            return nil
        }

        let localRect = CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
        let globalRect = localRect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
        return CaptureSelection(
            displayID: displayID,
            screenFrame: screen.frame,
            rect: globalRect,
            scale: screen.backingScaleFactor
        )
    }
}
