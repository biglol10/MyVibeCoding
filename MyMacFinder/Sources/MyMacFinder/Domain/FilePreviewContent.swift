import Foundation

public enum FilePreviewContent: Equatable, Sendable {
    case text(FileTextPreview)
    case visual
    case unsupported(message: String)
}

public struct FileTextPreview: Equatable, Sendable {
    public let text: String
    public let isTruncated: Bool
    public let byteLimit: Int
    public let encodingName: String

    public init(text: String, isTruncated: Bool, byteLimit: Int, encodingName: String) {
        self.text = text
        self.isTruncated = isTruncated
        self.byteLimit = byteLimit
        self.encodingName = encodingName
    }
}
