import Foundation
import Testing
@testable import MyMarkdownCore

struct FolderSearchTests {
    @Test func searchMemoryLimitsAreExplicitAndCannotAuthorizeReplace() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a.md", "b.md", "c.md"] { try Data("needle 12345".utf8).write(to: root.appendingPathComponent(name)) }
        let perFile = await FolderSearch.scan(folder: root, options: .init(query: "needle", maximumFileBytes: 5))
        #expect(perFile.files.isEmpty); #expect(!perFile.issues.isEmpty)
        let retained = await FolderSearch.scan(folder: root, options: .init(query: "needle", maximumRetainedBytes: 15))
        #expect(retained.files.count == 1); #expect(retained.isTruncated); #expect(!retained.wasCancelled)
        #expect(!retained.isComplete)
    }

    @Test func unicodeOffsetsLineColumnsAndPreviewPreserveCRLFBOM() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("doc.md")
        try (Data([0xEF, 0xBB, 0xBF]) + Data("첫 줄\r\n😀 한글 target\r\n".utf8)).write(to: file)
        let report = await FolderSearch.scan(folder: root, options: .init(query: "target"))
        let match = try #require(report.files.first?.matches.first)
        #expect(match.range == 10..<16); #expect(match.line == 2); #expect(match.column == 7); #expect(match.snippet == "😀 한글 target")
        let output = try FolderSearch.preview(try #require(report.replacementPlan.files.first), replacement: "바꿈")
        let bytes = try #require(report.replacementPlan.files.first).codec.encode(output)
        #expect(bytes.starts(with: [0xEF, 0xBB, 0xBF])); #expect(String(data: bytes.dropFirst(3), encoding: .utf8)?.contains("한글 바꿈\r\n") == true)
    }

    @Test func ignoresSymlinksAndReportsUnreadableCodec() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let good = root.appendingPathComponent("good.md"), link = root.appendingPathComponent("link.md"), bad = root.appendingPathComponent("bad.md")
        try Data("needle".utf8).write(to: good); try Data([0xFF]).write(to: bad); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: good)
        let report = await FolderSearch.scan(folder: root, options: .init(query: "needle"))
        #expect(report.files.map { $0.url.lastPathComponent } == ["good.md"])
        #expect(report.issues.map { $0.url.lastPathComponent } == ["bad.md"]); #expect(!report.isComplete)
    }

    @Test func truncationAndCaseOptionAreExplicit() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("Needle needle needle".utf8).write(to: root.appendingPathComponent("a.md"))
        let insensitive = await FolderSearch.scan(folder: root, options: .init(query: "needle", maximumResults: 2))
        #expect(insensitive.files.first?.matches.count == 2); #expect(insensitive.isTruncated)
        let sensitive = await FolderSearch.scan(folder: root, options: .init(query: "needle", caseSensitive: true))
        #expect(sensitive.files.first?.matches.count == 2)
    }

    @Test func thousandResultBoundaryOnlyTruncatesWhenThereIsAnotherMatch() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.md")
        try Data(String(repeating: "needle\n", count: 1_000).utf8).write(to: file)
        let exact = await FolderSearch.scan(folder: root, options: .init(query: "needle", maximumResults: 1_000))
        #expect(exact.files.first?.matches.count == 1_000); #expect(!exact.isTruncated)
        try Data(String(repeating: "needle\n", count: 1_001).utf8).write(to: file)
        let extra = await FolderSearch.scan(folder: root, options: .init(query: "needle", maximumResults: 1_000))
        #expect(extra.files.first?.matches.count == 1_000); #expect(extra.isTruncated)
    }

    @Test func cancelledScanIsExplicitlyIncomplete() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("needle".utf8).write(to: root.appendingPathComponent("a.md"))
        let task = Task { await FolderSearch.scan(folder: root, options: .init(query: "needle")) }
        task.cancel()
        #expect((await task.value).wasCancelled)
    }

    @Test func staleAndDeletedPlansCauseNoWritesDuringPreflight() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a.md"), b = root.appendingPathComponent("b.md"), store = FileStore(supportURL: root.appendingPathComponent("support"))
        try Data("needle".utf8).write(to: a); try Data("needle".utf8).write(to: b)
        let plan = (await FolderSearch.scan(folder: root, options: .init(query: "needle"))).replacementPlan
        try Data("external".utf8).write(to: a); try FileManager.default.removeItem(at: b)
        let result = await FolderSearch.apply(plan: plan, replacement: "changed", store: store)
        #expect(!result.preflightPassed); #expect(result.savedCount == 0); #expect(try String(contentsOf: a, encoding: .utf8) == "external")
        #expect(Set(result.outcomes.map(\.status)) == [.stale])
    }

    @Test func excludedFilesAreLeftUntouchedAndSelectedSave() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("a.md"), b = root.appendingPathComponent("b.md"), store = FileStore(supportURL: root.appendingPathComponent("support"))
        try Data("needle".utf8).write(to: a); try Data("needle".utf8).write(to: b)
        let plan = (await FolderSearch.scan(folder: root, options: .init(query: "needle"))).replacementPlan
        let result = await FolderSearch.apply(plan: plan, replacement: "changed", including: [a], store: store)
        #expect(result.preflightPassed); #expect(try String(contentsOf: a, encoding: .utf8) == "changed"); #expect(try String(contentsOf: b, encoding: .utf8) == "needle")
        #expect(result.outcomes.first { $0.url.lastPathComponent == "b.md" }?.status == .excluded)
    }

    @Test func parentSymlinkSwapCannotWriteOutsideScannedWorkspace() async throws {
        let root = try temporaryDirectory(), outside = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let subfolder = root.appendingPathComponent("sub"), scanned = subfolder.appendingPathComponent("note.md")
        let external = outside.appendingPathComponent("note.md")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try Data("needle".utf8).write(to: scanned); try Data("needle".utf8).write(to: external)
        let plan = (await FolderSearch.scan(folder: root, options: .init(query: "needle"))).replacementPlan
        try FileManager.default.moveItem(at: subfolder, to: root.appendingPathComponent("former-sub"))
        try FileManager.default.createSymbolicLink(at: subfolder, withDestinationURL: outside)
        let result = await FolderSearch.apply(plan: plan, replacement: "changed", store: FileStore(supportURL: root.appendingPathComponent("support")))
        #expect(!result.preflightPassed); #expect(result.savedCount == 0)
        #expect(try String(contentsOf: external, encoding: .utf8) == "needle")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FolderSearchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
}
