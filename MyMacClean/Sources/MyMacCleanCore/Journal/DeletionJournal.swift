import Foundation

public struct DeletionRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let appName: String
    public let bundleIdentifier: String?
    public let deletedAt: Date
    public let results: [DeletionItemResult]

    public init(id: UUID = UUID(), appName: String, bundleIdentifier: String?, deletedAt: Date = Date(), results: [DeletionItemResult]) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.deletedAt = deletedAt
        self.results = results
    }
}

public struct DeletionJournal: Sendable {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func append(_ record: DeletionRecord) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var data = try encoder.encode(record)
        data.append(0x0A)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: fileURL)
        }
    }

    public func readRecords() throws -> [DeletionRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return try text
            .split(separator: "\n")
            .map { line in
                let data = Data(line.utf8)
                return try decoder.decode(DeletionRecord.self, from: data)
            }
    }
}
