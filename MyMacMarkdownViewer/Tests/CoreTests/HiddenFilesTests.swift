import Foundation
import Testing
@testable import MyMarkdownCore

struct HiddenFilesTests {
    @Test func hiddenFileSettingMigratesAndPersists() throws {
        let previous = Data(#"{"theme":"night","fontSize":19,"autosave":false,"focusMode":true}"#.utf8)
        let migrated = try JSONDecoder().decode(ReadingSettings.self, from: previous)
        #expect(!migrated.showHiddenFiles)
        #expect(migrated.theme == .night && migrated.fontSize == 19 && !migrated.autosave && migrated.focusMode)
        #expect(!ReadingSettings().showHiddenFiles)
        for showHiddenFiles in [false, true] {
            var settings = migrated
            settings.showHiddenFiles = showHiddenFiles
            #expect(try JSONDecoder().decode(ReadingSettings.self, from: JSONEncoder().encode(settings)) == settings)
        }
    }

    @Test func treeAndIndexIncludeClaudeDocumentsOnlyWhenEnabled() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let documents = try writeWorkspace(at: root)
        #expect(try FolderScanner.children(of: root).map(\.name) == ["run", "CLAUDE.md", "README.md"])
        #expect(Set(try FolderScanner.children(of: root, showHiddenFiles: true).map(\.name)) == [".claude", "run", ".hidden.md", "CLAUDE.md", "README.md"])
        #expect(Set(FolderScanner.index(root).map(canonical)) == Set(documents.filter { !isHidden($0, inside: root) }.map(canonical)))
        #expect(Set(FolderScanner.index(root, showHiddenFiles: true).map(canonical)) == Set(documents.map(canonical)))
        let agents = root.appendingPathComponent(".claude/agents")
        #expect(try FolderScanner.children(of: agents, showHiddenFiles: true).map(\.name) == ["design-reviewer.md", "refactorer.md", "security-auditor.md", "static-analyzer.md"])
    }

    @Test func revealExpandsHiddenAncestorsUnderTheSelectedPolicy() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try writeWorkspace(at: root)
        for path in [".claude/agents/design-reviewer.md", ".claude/skills/code-review-team/SKILL.md", ".hidden.md"] {
            let target = root.appendingPathComponent(path)
            #expect(throws: CocoaError.self) { try FileTreeReveal.read(document: target, inside: root) }
            let snapshot = try FileTreeReveal.read(document: target, inside: root, showHiddenFiles: true)
            #expect(canonical(snapshot.target) == canonical(target))
            #expect(snapshot.directories.map(canonical) == FileTreeReveal.directories(for: target, inside: root)?.map(canonical))
            let children = snapshot.entries.filter { $0.key != root.path }
            let rows = FileTreeProjection.rows(roots: snapshot.entries[root.path]!, children: children, expanded: Set(snapshot.directories.dropFirst().map(\.path)))
            #expect(rows.contains { $0.id == snapshot.target.path })
        }
    }

    @Test func searchUsesTheSameHiddenPolicyAndReplacesSelectedHiddenDocuments() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let documents = try writeWorkspace(at: root)
        let hidden = root.appendingPathComponent(".claude/skills/code-review-team/SKILL.md")
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("needle\r\n한글\r\n".utf8)
        try original.write(to: hidden)
        let visible = await FolderSearch.scan(folder: root, options: .init(query: "needle"))
        #expect(visible.isComplete)
        #expect(Set(visible.files.map { canonical($0.url) }) == Set(documents.filter { !isHidden($0, inside: root) }.map(canonical)))
        #expect(visible.files.allSatisfy { !$0.showHiddenFiles })
        let all = await FolderSearch.scan(folder: root, options: .init(query: "needle", showHiddenFiles: true))
        #expect(all.isComplete)
        #expect(Set(all.files.map { canonical($0.url) }) == Set(documents.map(canonical)))
        #expect(all.replacementPlan.files.allSatisfy { $0.showHiddenFiles })
        let applied = await FolderSearch.apply(plan: all.replacementPlan, replacement: "changed", including: [hidden], store: FileStore(supportURL: root.appendingPathComponent("support")))
        #expect(applied.preflightPassed && applied.savedCount == 1)
        #expect(try Data(contentsOf: hidden) == Data([0xEF, 0xBB, 0xBF]) + Data("changed\r\n한글\r\n".utf8))
        for document in documents where document != hidden {
            #expect(try String(contentsOf: document, encoding: .utf8) == "needle")
        }
    }

    @Test func enabledHiddenPolicyStillExcludesSymlinksAndPackages() async throws {
        let root = try temporaryDirectory(), outside = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let documents = try writeWorkspace(at: root)
        let external = outside.appendingPathComponent("outside.md")
        try Data("needle".utf8).write(to: external)
        let linkedFile = root.appendingPathComponent(".alias.md")
        let linkedDirectory = root.appendingPathComponent(".claude/linked")
        try FileManager.default.createSymbolicLink(at: linkedFile, withDestinationURL: external)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: outside)
        for name in ["Sample.app", ".Hidden.app"] {
            let package = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            try Data("needle".utf8).write(to: package.appendingPathComponent("inside.md"))
            #expect(try package.resourceValues(forKeys: [.isPackageKey]).isPackage == true)
        }
        for showHiddenFiles in [false, true] {
            let expected = Set(documents.filter { showHiddenFiles || !isHidden($0, inside: root) }.map(canonical))
            #expect(Set(FolderScanner.index(root, showHiddenFiles: showHiddenFiles).map(canonical)) == expected)
            let report = await FolderSearch.scan(folder: root, options: .init(query: "needle", showHiddenFiles: showHiddenFiles))
            #expect(report.isComplete && Set(report.files.map { canonical($0.url) }) == expected)
            let entries = try FolderScanner.children(of: root, showHiddenFiles: showHiddenFiles)
            #expect(!entries.contains { $0.name == ".alias.md" || $0.name == "Sample.app" || $0.name == ".Hidden.app" })
            for target in [linkedFile, linkedDirectory.appendingPathComponent("outside.md"), root.appendingPathComponent("Sample.app/inside.md"), root.appendingPathComponent(".Hidden.app/inside.md")] {
                #expect(throws: CocoaError.self) { try FileTreeReveal.read(document: target, inside: root, showHiddenFiles: showHiddenFiles) }
            }
        }
    }

    @Test func hiddenReplacementRejectsParentSymlinkSwappedAfterSearch() async throws {
        let root = try temporaryDirectory(), outside = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let directory = root.appendingPathComponent(".claude/agents")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let document = directory.appendingPathComponent("reviewer.md"), external = outside.appendingPathComponent("reviewer.md")
        try Data("needle".utf8).write(to: document); try Data("needle".utf8).write(to: external)
        let report = await FolderSearch.scan(folder: root, options: .init(query: "needle", showHiddenFiles: true))
        #expect(report.files.count == 1)
        try FileManager.default.moveItem(at: directory, to: root.appendingPathComponent("former-agents"))
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: outside)
        let applied = await FolderSearch.apply(plan: report.replacementPlan, replacement: "changed", store: FileStore(supportURL: root.appendingPathComponent("support")))
        #expect(!applied.preflightPassed && applied.savedCount == 0)
        #expect(try String(contentsOf: external, encoding: .utf8) == "needle")
    }

    private func writeWorkspace(at root: URL) throws -> [URL] {
        let paths = ["README.md", "CLAUDE.md", "run/checklist.md", ".hidden.md", ".claude/agents/design-reviewer.md", ".claude/agents/refactorer.md", ".claude/agents/security-auditor.md", ".claude/agents/static-analyzer.md", ".claude/skills/code-review-team/SKILL.md"]
        return try paths.map { path in
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("needle".utf8).write(to: url)
            return url
        }
    }

    private func isHidden(_ document: URL, inside root: URL) -> Bool {
        document.pathComponents.dropFirst(root.pathComponents.count).contains { $0.hasPrefix(".") }
    }

    private func canonical(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("HiddenFilesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }
}
