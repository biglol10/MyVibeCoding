import Foundation

public enum FilePreviewContent: Equatable, Sendable {
    case text(FileTextPreview)
    case visual
    case unsupported(message: String)
}

public enum FilePreviewByteLimit: Int, Codable, CaseIterable, Identifiable, Sendable {
    case compact = 16_384
    case balanced = 65_536
    case expanded = 262_144
    case large = 1_048_576

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .compact:
            return "16 KB"
        case .balanced:
            return "64 KB"
        case .expanded:
            return "256 KB"
        case .large:
            return "1 MB"
        }
    }
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
