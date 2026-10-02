import Foundation
import XCTest
@testable import PaneHarbor

final class ReleaseSafetyEdgeTests: XCTestCase {
    func testRenameDotNamesRejectsBeforeOfferingToReplaceParentDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RenameDot-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.txt")
        try Data("must survive".utf8).write(to: source)
        let resolver = RecordingCancelResolver()
        for name in [".", "..", "  ..  "] {
            do {
                _ = try await FileOperationService(conflictResolver: resolver).rename(source, to: name)
                XCTFail("Invalid leaf name was accepted")
            } catch let error as ExplorerError {
                guard case .invalidPath = error else { XCTFail("Expected invalidPath, got \(error)"); continue }
            } catch { XCTFail("Invalid names must be rejected before conflict resolution: \(error)") }
        }
        let calls = await resolver.calls
        XCTAssertEqual(calls, 0, "A parent directory must never be offered as a replace target")
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "must survive")
    }

    func testSpecialUnicodeNamesCopyRenameMoveAndCaseOnlyRenamePreserveBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("UnicodeOps-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let names = ["한글 공백 % + # & ?.txt", "한글.txt", "emoji 👨‍👩‍👧‍👦.txt", ".hidden", "zero"]
        let service = FileOperationService()
        for (index, name) in names.enumerated() {
            let url = source.appendingPathComponent(name)
            let data = index == 4 ? Data() : Data((0..<513).map { UInt8(($0 + index) % 256) })
            try data.write(to: url)
            let result = try await service.copyItems([url], to: destination)
            let copied = try XCTUnwrap(result.createdURLs.first)
            XCTAssertEqual(try Data(contentsOf: copied), data)
            let renameResult = try await service.rename(copied, to: "Renamed \(index).txt")
            let renamed = try XCTUnwrap(renameResult.renamedItem?.destination)
            XCTAssertEqual(try Data(contentsOf: renamed), data)
            let changedCase = try await service.rename(renamed, to: "RENAMED \(index).TXT")
            let final = try XCTUnwrap(changedCase.renamedItem?.destination)
            XCTAssertEqual(try Data(contentsOf: final), data)
            let moved = try await service.moveItems([final], to: source)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(moved.movedItems.first).destination), data)
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }
}

private actor RecordingCancelResolver: FileConflictResolving {
    private(set) var calls = 0
    func resolve(_ conflict: FileConflict) async throws -> FileConflictDecision {
        calls += 1
        throw FileOperationCancellation(operation: conflict.operation)
    }
}
