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
