import XCTest
@testable import MyMacCleanCore

final class DeletionJournalTests: XCTestCase {
    func testAppendsAndReadsDeletionRecords() throws {
        let root = try TestFixtures.temporaryDirectory(named: "journal")
        let journalURL = root.appendingPathComponent("deletions.jsonl")
        let journal = DeletionJournal(fileURL: journalURL)
        let app = InstalledApp(displayName: "Figma", bundleIdentifier: "com.figma.Desktop", version: "124", executableName: "Figma", bundleURL: URL(fileURLWithPath: "/Applications/Figma.app"), iconIdentifier: nil, bundleSize: 0, lastOpenedAt: nil)
        let record = DeletionRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            appName: app.displayName,
            bundleIdentifier: app.bundleIdentifier,
            deletedAt: Date(timeIntervalSince1970: 1),
            results: [DeletionItemResult(path: "/tmp/cache", success: true, errorMessage: nil)]
        )

        try journal.append(record)
        let records = try journal.readRecords()

        XCTAssertEqual(records, [record])
    }
}
