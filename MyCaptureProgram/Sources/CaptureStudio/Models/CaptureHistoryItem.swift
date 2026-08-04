import Darwin
import Foundation

public struct CaptureFileIdentity: Codable, Equatable, Sendable {
    public let device: UInt64
    public let inode: UInt64

    public static func existingFile(at url: URL) throws -> CaptureFileIdentity {
        var information = stat()
        let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else {
                errno = EINVAL
                return -1
            }
            return Darwin.lstat(path, &information)
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return CaptureFileIdentity(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino)
        )
    }

    public func matchesExistingFile(at url: URL) -> Bool {
        (try? Self.existingFile(at: url)) == self
    }
}

public struct CaptureHistoryItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var kind: EditorDocument.Kind
    public var createdAt: Date
    public var fileURL: URL
    public var title: String
    public var detail: String
    public var fileIdentity: CaptureFileIdentity?
    public var thumbnailURL: URL?
    public var thumbnailData: Data?
    public var sourceApplication: String?
    public var windowTitle: String?

    public init(
        id: UUID = UUID(),
        kind: EditorDocument.Kind,
        createdAt: Date,
        fileURL: URL,
        title: String,
        detail: String,
        fileIdentity: CaptureFileIdentity? = nil,
        thumbnailURL: URL? = nil,
        thumbnailData: Data? = nil,
        sourceApplication: String? = nil,
        windowTitle: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.fileURL = fileURL
        self.title = title
        self.detail = detail
        self.fileIdentity = fileIdentity
        self.thumbnailURL = thumbnailURL
        self.thumbnailData = thumbnailData
        self.sourceApplication = sourceApplication
        self.windowTitle = windowTitle
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case createdAt
        case fileURL
        case title
        case detail
        case fileIdentity
        case thumbnailURL
        case sourceApplication
        case windowTitle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(EditorDocument.Kind.self, forKey: .kind)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        fileURL = try container.decode(URL.self, forKey: .fileURL)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decode(String.self, forKey: .detail)
        fileIdentity = try container.decodeIfPresent(CaptureFileIdentity.self, forKey: .fileIdentity)
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        thumbnailData = nil
        sourceApplication = try container.decodeIfPresent(String.self, forKey: .sourceApplication)
        windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(fileURL, forKey: .fileURL)
        try container.encode(title, forKey: .title)
        try container.encode(detail, forKey: .detail)
        try container.encodeIfPresent(fileIdentity, forKey: .fileIdentity)
        try container.encodeIfPresent(thumbnailURL, forKey: .thumbnailURL)
        try container.encodeIfPresent(sourceApplication, forKey: .sourceApplication)
        try container.encodeIfPresent(windowTitle, forKey: .windowTitle)
    }

    public var searchableText: String {
        [
            title,
            detail,
            sourceApplication,
            windowTitle,
            fileURL.lastPathComponent
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }
}
