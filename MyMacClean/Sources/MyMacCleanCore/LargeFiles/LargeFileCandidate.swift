import Foundation

public enum LargeFileKind: String, CaseIterable, Codable, Equatable, Sendable {
    case archive
    case diskImage
    case video
    case audio
    case document
    case image
    case other

    public static func infer(from url: URL) -> LargeFileKind {
        switch url.pathExtension.lowercased() {
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz":
            return .archive
        case "dmg", "iso":
            return .diskImage
        case "mov", "mp4", "m4v", "avi", "mkv":
            return .video
        case "mp3", "m4a", "wav", "aiff", "flac":
            return .audio
        case "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "pages", "numbers", "key":
            return .document
        case "png", "jpg", "jpeg", "heic", "tiff", "gif", "webp":
            return .image
        default:
            return .other
        }
    }
}

public enum LargeFileSort: String, CaseIterable, Identifiable, Sendable {
    case sizeDescending
    case modifiedDescending
    case pathAscending

    public var id: Self { self }

    public var title: String {
        switch self {
        case .sizeDescending: "Size"
        case .modifiedDescending: "Modified"
        case .pathAscending: "Path"
        }
    }
}

public struct LargeFileCandidate: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let size: Int64
    public let modifiedAt: Date?
    public let kind: LargeFileKind
    public let rootURL: URL
    public let defaultSelected: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        size: Int64,
        modifiedAt: Date?,
        kind: LargeFileKind,
        rootURL: URL,
        defaultSelected: Bool = false
    ) {
        self.id = id
        self.url = url
        self.size = size
        self.modifiedAt = modifiedAt
        self.kind = kind
        self.rootURL = rootURL
        self.defaultSelected = defaultSelected
    }
}
