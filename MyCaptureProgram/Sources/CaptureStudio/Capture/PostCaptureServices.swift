import AppKit
import Foundation

@MainActor
public protocol ClipboardServicing {
    func copyPNGData(_ data: Data)
    func copyText(_ text: String)
}

public struct PasteboardClipboardService: ClipboardServicing {
    public init() {}

    public func copyPNGData(_ data: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }

    public func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

@MainActor
public protocol FileRevealServicing {
    func reveal(_ url: URL)
}

public struct WorkspaceFileRevealService: FileRevealServicing {
    public init() {}

    public func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

@MainActor
public protocol FileTrashServicing {
    func trash(_ url: URL) throws
}

public struct WorkspaceFileTrashService: FileTrashServicing {
    public init() {}

    public func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

@MainActor
public protocol CaptureWindowVisibilityControlling {
    func hideCaptureWindows()
    func hideCaptureWindows(excluding excludedWindow: NSWindow?)
    func restoreCaptureWindows()
}

public extension CaptureWindowVisibilityControlling {
    func hideCaptureWindows(excluding excludedWindow: NSWindow?) {
        hideCaptureWindows()
    }
}

@MainActor
public final class AppKitCaptureWindowVisibilityController: CaptureWindowVisibilityControlling {
    private var hiddenWindows: [NSWindow] = []
    private var isCaptureWindowSuppressionActive = false
    private let windowProvider: @MainActor () -> [NSWindow]

    public convenience init() {
        self.init(windowProvider: { NSApp?.windows ?? [] })
    }

    init(windowProvider: @escaping @MainActor () -> [NSWindow]) {
        self.windowProvider = windowProvider
    }

    public func hideCaptureWindows() {
        isCaptureWindowSuppressionActive = true
        hideVisibleCaptureWindows(excluding: nil)
    }

    public func hideCaptureWindows(excluding excludedWindow: NSWindow?) {
        guard isCaptureWindowSuppressionActive else {
            return
        }

        hideVisibleCaptureWindows(excluding: excludedWindow)
    }

    private func hideVisibleCaptureWindows(excluding excludedWindow: NSWindow?) {
        let windowsToHide = windowProvider().filter { window in
            window !== excludedWindow
                && window.isVisible
                && !(window is NSPanel)
                && window.styleMask.rawValue != NSWindow.StyleMask.borderless.rawValue
        }

        for window in windowsToHide {
            if !hiddenWindows.contains(where: { $0 === window }) {
                hiddenWindows.append(window)
            }
            window.orderOut(nil)
        }
    }

    public func restoreCaptureWindows() {
        hiddenWindows.forEach { window in
            window.makeKeyAndOrderFront(nil)
        }
        hiddenWindows.removeAll()
        isCaptureWindowSuppressionActive = false
    }
}
