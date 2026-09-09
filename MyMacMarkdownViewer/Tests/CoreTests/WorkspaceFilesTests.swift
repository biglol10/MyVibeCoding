import Foundation
import Testing
@testable import MyMarkdownCore

struct WorkspaceFilesTests {
    @Test func createsMarkdownDocumentAndFolderInsideWorkspace() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceFiles()
        let folder = try await service.createFolder(root: root, directory: root, name: "자료 모음")
        let document = try await service.createDocument(root: root, directory: folder, name: "오늘의 기록")
        #expect(folder.lastPathComponent == "자료 모음")
        #expect(document.lastPathComponent == "오늘의 기록.md")
        #expect(FileManager.default.fileExists(atPath: document.path))
    }

    @Test func rejectsDuplicateNamesWithoutReplacingExistingItem() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceFiles()
        let original = root.appendingPathComponent("Note.md")
        try Data("keep".utf8).write(to: original)
        await #expect(throws: WorkspaceFileError.alreadyExists) {
            try await service.createDocument(root: root, directory: root, name: "note")
        }
        #expect(try String(contentsOf: original, encoding: .utf8) == "keep")
    }

    @Test func movesToExactDestinationAndSupportsCaseOnlyRename() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceFiles()
        let source = root.appendingPathComponent("draft.md")
        try Data("내용".utf8).write(to: source)
        let renamed = try await service.move(root: root, source: source, destination: root.appendingPathComponent("DRAFT.md"))
        #expect(renamed.lastPathComponent == "DRAFT.md")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["DRAFT.md"])
        #expect(try String(contentsOf: renamed, encoding: .utf8) == "내용")
    }

    @Test func failedCaseOnlyRenameRollsBackWithoutDeletingTheSource() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("draft.md")
        try Data("보존".utf8).write(to: source)
        let spy = MoveSpy(failures: [2])
        let service = WorkspaceFiles(fileManager: .default, moveItem: spy.move)

        await #expect(throws: WorkspaceFileError.renameFailed) {
            try await service.move(root: root, source: source, destination: root.appendingPathComponent("DRAFT.md"))
        }
        #expect(try String(contentsOf: source, encoding: .utf8) == "보존")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["draft.md"])
    }

    @Test func failedRollbackReportsRecoverableTemporaryPath() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("draft.md")
        try Data("보존".utf8).write(to: source)
        let spy = MoveSpy(failures: [2, 3])
        let service = WorkspaceFiles(fileManager: .default, moveItem: spy.move)

        do {
            _ = try await service.move(root: root, source: source, destination: root.appendingPathComponent("DRAFT.md"))
            Issue.record("Expected a recovery error")
        } catch let WorkspaceFileError.renameRecoveryRequired(temporary) {
            #expect(FileManager.default.fileExists(atPath: temporary.path))
            #expect(try String(contentsOf: temporary, encoding: .utf8) == "보존")
        }
    }

    @Test func rejectsOutsidePathsSymlinkComponentsAndInvalidNames() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let outside = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: outside) }
        let service = WorkspaceFiles()
        let linkedFolder = root.appendingPathComponent("outside-link")
        try FileManager.default.createSymbolicLink(at: linkedFolder, withDestinationURL: outside)
        await #expect(throws: WorkspaceFileError.unsafePath) {
            try await service.createDocument(root: root, directory: linkedFolder, name: "blocked")
        }
        await #expect(throws: WorkspaceFileError.unsafePath) {
            try await service.createFolder(root: root, directory: outside, name: "blocked")
        }
        await #expect(throws: WorkspaceFileError.invalidName) {
            try await service.createFolder(root: root, directory: root, name: "../unsafe")
        }
    }

    @Test func rejectsRootTrashAndDirectoryMoveIntoItself() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceFiles()
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        await #expect(throws: WorkspaceFileError.rootProtected) {
            try await service.trash(root: root, source: root)
        }
        await #expect(throws: WorkspaceFileError.invalidMove) {
            try await service.move(root: root, source: folder, destination: folder.appendingPathComponent("nested/folder"))
        }
    }

    @Test func listsHiddenMarkdownBeforeFolderRelocationAndSkipsLinks() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("visible".utf8).write(to: folder.appendingPathComponent("note.md"))
        try Data("hidden".utf8).write(to: folder.appendingPathComponent(".draft.md"))
        let outside = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: outside) }
        try Data("outside".utf8).write(to: outside.appendingPathComponent("outside.md"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("linked"), withDestinationURL: outside)

        let documents = try await WorkspaceFiles().markdownDocuments(root: root, source: folder)
        #expect(documents.map(\.lastPathComponent) == [".draft.md", "note.md"])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("WorkspaceFilesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private final class MoveSpy: @unchecked Sendable {
        private var invocation = 0
        private let failures: Set<Int>

        init(failures: Set<Int>) { self.failures = failures }

        lazy var move: @Sendable (URL, URL) throws -> Void = { [self] source, destination in
            invocation += 1
            if failures.contains(invocation) { throw WorkspaceFileError.unavailable }
            try FileManager.default.moveItem(at: source, to: destination)
        }
    }
}
