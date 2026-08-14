import Foundation
@testable import MyMacSearchCore

struct TemporaryIndexFixture {
    let rootURL: URL
    let databaseURL: URL
    let writer: SQLiteIndexWriter
    let reader: SQLiteIndexReader

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacSearchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        databaseURL = rootURL.appendingPathComponent("index.sqlite3")
        writer = try SQLiteIndexWriter(databaseURL: databaseURL)
        reader = try SQLiteIndexReader(databaseURL: databaseURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

extension IndexedEntry {
    static func testEntry(
        path: String,
        scopeID: String = "home",
        kind: IndexedFileKind? = nil,
        sizeBytes: Int64 = 100,
        modifiedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        generation: Int64 = 1
    ) -> IndexedEntry {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let isDirectory = kind == .folder
        return IndexedEntry(
            scopeID: scopeID,
            path: path,
            parentPath: url.deletingLastPathComponent().path,
            name: name,
            fileExtension: url.pathExtension,
            kind: kind ?? FileKindClassifier.kind(name: name, isDirectory: isDirectory, isPackage: false),
            sizeBytes: sizeBytes,
            modifiedAt: modifiedAt,
            isDirectory: isDirectory,
            isSymlink: false,
            isPackage: false,
            isHidden: false,
            scanGeneration: generation
        )
    }
}
