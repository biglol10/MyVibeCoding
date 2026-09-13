import Foundation
import Testing
@testable import MyMarkdownCore

struct FileTreeRevealTests {
    @Test func plansOnlyAncestorsAndAcceptsRootLevelFiles() throws {
        let root = URL(fileURLWithPath: "/notes", isDirectory: true)
        let nested = root.appendingPathComponent("한글 폴더/deep/note.md")
        #expect(FileTreeReveal.directories(for: nested, inside: root)?.map(\.path) == ["/notes", "/notes/한글 폴더", "/notes/한글 폴더/deep"])
        #expect(FileTreeReveal.directories(for: root.appendingPathComponent("note.md"), inside: root)?.map(\.path) == ["/notes"])
    }

    @Test func rejectsOutsideRootsPrefixSiblingsAndTraversal() {
        let root = URL(fileURLWithPath: "/notes", isDirectory: true)
        for path in ["/notes-other/note.md", "/notes/../elsewhere/note.md", "/notes"] {
            #expect(FileTreeReveal.directories(for: URL(fileURLWithPath: path), inside: root) == nil)
        }
        #expect(FileTreeReveal.directories(for: URL(string: "https://example.com/notes/a.md")!, inside: root) == nil)
    }

    @Test func readsCollapsedAncestorChainWithoutUnrelatedSubtrees() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("A/B/current.MD")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# current".utf8).write(to: target)
        let unrelated = root.appendingPathComponent("unrelated/deep", isDirectory: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try Data("# unrelated".utf8).write(to: unrelated.appendingPathComponent("other.md"))
        let snapshot = try FileTreeReveal.read(document: target, inside: root)
        #expect(snapshot.target.standardizedFileURL.resolvingSymlinksInPath() == target.standardizedFileURL.resolvingSymlinksInPath())
        #expect(snapshot.entries.count == 3)
        #expect(snapshot.entries[unrelated.deletingLastPathComponent().path] == nil)
        let children = snapshot.entries.filter { $0.key != root.path }
        let rows = FileTreeProjection.rows(roots: snapshot.entries[root.path]!, children: children, expanded: Set(snapshot.directories.dropFirst().map(\.path)))
        #expect(rows.contains { $0.id == snapshot.target.path && $0.depth == 2 })
        #expect(try Data(contentsOf: target) == Data("# current".utf8))
    }

    @Test func missingHiddenAndSymlinkedTargetsDoNotInventVisibleRows() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let hidden = root.appendingPathComponent(".hidden.md")
        let original = root.appendingPathComponent("original.md")
        try Data("# source".utf8).write(to: hidden); try Data("# source".utf8).write(to: original)
        let alias = root.appendingPathComponent("alias.md")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
        for target in [hidden, alias, root.appendingPathComponent("missing.md")] {
            #expect(throws: CocoaError.self) { try FileTreeReveal.read(document: target, inside: root) }
        }
    }
}
