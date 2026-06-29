import Foundation

public enum FileClipboardMode: String, Codable, Sendable {
    case copy
    case move
}

public struct FileClipboard: Equatable, Sendable {
    public var urls: [URL]
    public var mode: FileClipboardMode

    public init(urls: [URL], mode: FileClipboardMode) {
        self.urls = urls
        self.mode = mode
    }

    public var isEmpty: Bool {
        urls.isEmpty
    }
}
