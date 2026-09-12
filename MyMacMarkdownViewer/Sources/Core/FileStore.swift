import Foundation

public struct DiskDocument: Sendable {
    public let url: URL
    public let codec: DocumentCodec
    public var hash: String { DocumentCodec.hash(codec.originalData) }
}

public struct RecoveryRecord: Codable, Sendable, Identifiable {
    public let id: String
    public var path: String?
    public var text: String
    public var codec: DocumentCodec
    public var revision: Int
    public var date: Date
    public init(id: String, path: String?, text: String, codec: DocumentCodec, revision: Int, date: Date = .now) {
        self.id = id; self.path = path; self.text = text; self.codec = codec; self.revision = revision; self.date = date
    }
}

public actor FileStore {
    public let supportURL: URL
    private let fm = FileManager.default
    public init(supportURL: URL) { self.supportURL = supportURL }

    public func read(_ url: URL) throws -> DiskDocument {
        try Self.validateRegularFile(url)
        var coordinationError: NSError?
        var outcome: Result<Data, Error> = .failure(DocumentError.unavailable)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            outcome = Result { try Data(contentsOf: coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        return try DiskDocument(url: url, codec: DocumentCodec(data: outcome.get()))
    }

    public func save(_ url: URL, text: String, codec: DocumentCodec, expectedHash: String?) throws -> DiskDocument {
        let bytes = codec.encode(text)
        var coordinationError: NSError?
        var outcome: Result<Void, Error> = .failure(DocumentError.unavailable)
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            outcome = Result {
                let exists = fm.fileExists(atPath: target.path)
                if exists {
                    try Self.validateRegularFile(target)
                    guard let expectedHash else { throw DocumentError.conflict }
                    let before = try Data(contentsOf: target)
                    guard DocumentCodec.hash(before) == expectedHash else { throw DocumentError.conflict }
                    try backup(before, for: target)
                } else if expectedHash != nil { throw DocumentError.deleted }
                // A user-selected file grants access to that file, not arbitrary
                // siblings. Foundation provides a writable staging directory on
                // the destination volume for a coordinated atomic replacement.
                let staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
                let temp = staging.appendingPathComponent("document.tmp")
                defer { try? fm.removeItem(at: staging) }
                try bytes.write(to: temp, options: .withoutOverwriting)
                // Recheck after writing the temporary file to narrow races with uncoordinated writers.
                if exists {
                    try Self.validateRegularFile(target)
                    guard DocumentCodec.hash(try Data(contentsOf: target)) == expectedHash else { throw DocumentError.conflict }
                    _ = try fm.replaceItemAt(target, withItemAt: temp)
                } else {
                    guard !fm.fileExists(atPath: target.path) else { throw DocumentError.conflict }
                    try fm.moveItem(at: temp, to: target)
                }
            }
        }
        if let coordinationError { throw coordinationError }
        try outcome.get()
        return try DiskDocument(url: url, codec: DocumentCodec(data: bytes))
    }

    private func backup(_ data: Data, for url: URL) throws {
        let key = DocumentCodec.hash(Data(url.path.utf8))
        let directory = supportURL.appendingPathComponent("Backups/\(key)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(Date.now.timeIntervalSince1970)-\(UUID().uuidString).md")
        try data.write(to: file, options: .atomic)
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in files.dropFirst(5) { try? fm.removeItem(at: old) }
    }

    public func writeRecovery(_ record: RecoveryRecord) throws {
        let dir = supportURL.appendingPathComponent("Recovery")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: dir.appendingPathComponent(record.id + ".json"), options: .atomic)
    }

    public func removeRecovery(_ id: String) throws {
        let file = supportURL.appendingPathComponent("Recovery/\(id).json")
        if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
    }

    public func recoveries() throws -> [RecoveryRecord] {
        let dir = supportURL.appendingPathComponent("Recovery")
        guard fm.fileExists(atPath: dir.path) else { return [] }
        return try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(RecoveryRecord.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    public static func validateRegularFile(_ url: URL) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular else { throw DocumentError.unsafePath }
    }
}
