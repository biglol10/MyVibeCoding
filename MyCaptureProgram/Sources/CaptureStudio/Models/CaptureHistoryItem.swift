import Foundation

public struct CaptureHistoryItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var kind: EditorDocument.Kind
    public var createdAt: Date
    public var fileURL: URL
    public var title: String
    public var detail: String
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
        self.thumbnailData = thumbnailData
        self.sourceApplication = sourceApplication
        self.windowTitle = windowTitle
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
