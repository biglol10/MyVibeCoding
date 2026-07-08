import Foundation

public enum FilePreviewContent: Equatable, Sendable {
    case text(FileTextPreview)
    case visual
    case unsupported(message: String)
}

public enum FilePreviewMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case smart
    case textOnly
    case off

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .smart:
            return "Smart"
        case .textOnly:
            return "Text Only"
        case .off:
            return "Off"
        }
    }
}

public enum FilePreviewAvailability: Equatable, Sendable {
    case available
    case unavailable(message: String)

    public var message: String? {
        guard case .unavailable(let message) = self else {
            return nil
        }
        return message
    }
}

public enum FilePreviewPolicy {
    public static let defaultLargeVisualPreviewLimitBytes: Int64 = 50 * 1_024 * 1_024

    public static func contentAvailability(mode: FilePreviewMode) -> FilePreviewAvailability {
        switch mode {
        case .smart, .textOnly:
            return .available
        case .off:
            return .unavailable(message: "Preview disabled in Settings.")
        }
    }

    public static func thumbnailAvailability(
        for entry: FileEntry,
        mode: FilePreviewMode,
        largeFileLimit: Int64 = defaultLargeVisualPreviewLimitBytes
    ) -> FilePreviewAvailability {
        switch mode {
        case .off:
            return .unavailable(message: "Preview disabled in Settings.")
        case .textOnly:
            return .unavailable(message: "Visual previews disabled. Use Quick Look to preview this file.")
        case .smart:
            guard !entry.isDirectoryLike,
                  let size = entry.size,
                  size > largeFileLimit else {
                return .available
            }
            return .unavailable(message: "Large file preview skipped. Use Quick Look to preview this file.")
        }
    }
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
