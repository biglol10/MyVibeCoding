import AppKit
import Foundation

@MainActor
public protocol FloatingPinServicing {
    func pinImage(data: Data, title: String) throws
}

public enum FloatingPinError: LocalizedError, Equatable {
    case imageDecodeFailed

    public var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:
            return "The screenshot could not be opened as an image."
        }
    }
}

@MainActor
public final class AppKitFloatingPinService: FloatingPinServicing {
    private var panels: [NSPanel] = []

    public init() {}

    public func pinImage(data: Data, title: String) throws {
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            throw FloatingPinError.imageDecodeFailed
        }

        let maxSize = NSSize(width: 720, height: 520)
        let scale = min(maxSize.width / image.size.width, maxSize.height / image.size.height, 1)
        let contentSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: contentSize))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = imageView
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        panels.append(panel)
    }
}
