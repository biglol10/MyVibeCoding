import Foundation
import Testing
@testable import MyMarkdownCore

struct FileTreeProjectionTests {
    private func entry(_ name: String, directory: Bool) -> FileEntry {
        FileEntry(url: URL(fileURLWithPath: "/projection-test/\(name)"), isDirectory: directory)
    }

    @Test func preservesInputOrderAndProjectsExpandedDescendantsAtTheirDepth() {
        let root = entry("A-folder", directory: true)
        let sibling = entry("z-note.md", directory: false)
        let nested = entry("A-folder/B-folder", directory: true)
        let child = entry("A-folder/first.md", directory: false)
        let grandchild = entry("A-folder/B-folder/deep.md", directory: false)
        let last = entry("A-folder/last.md", directory: false)

        let rows = FileTreeProjection.rows(
            roots: [root, sibling],
            children: [root.id: [nested, child, last], nested.id: [grandchild]],
            expanded: [root.id, nested.id]
        )

        #expect(rows.map(\.entry) == [root, nested, grandchild, child, last, sibling])
        #expect(rows.map(\.depth) == [0, 1, 2, 1, 1, 0])
    }

    @Test func collapsedAndEmptyFoldersRemainVisibleWithoutShowingHiddenChildren() {
        let collapsed = entry("collapsed", directory: true)
        let empty = entry("empty", directory: true)
        let hidden = entry("collapsed/hidden.md", directory: false)

        let rows = FileTreeProjection.rows(
            roots: [collapsed, empty],
            children: [collapsed.id: [hidden]],
            expanded: [empty.id]
        )

        #expect(rows.map(\.entry) == [collapsed, empty])
        #expect(rows.map(\.depth) == [0, 0])
    }

    @Test func duplicateIDsAreEmittedOnlyOnce() {
        let folder = entry("folder", directory: true)
        let first = entry("folder/duplicate.md", directory: false)
        let duplicate = FileEntry(url: first.url, isDirectory: false)

        let rows = FileTreeProjection.rows(
            roots: [folder, first],
            children: [folder.id: [duplicate]],
            expanded: [folder.id]
        )

        #expect(rows.map(\.id) == [folder.id, first.id])
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test func malformedCyclesTerminateAndDoNotRepeatRows() {
        let first = entry("first", directory: true)
        let second = entry("first/second", directory: true)
        let backEdge = FileEntry(url: first.url, isDirectory: true)

        let rows = FileTreeProjection.rows(
            roots: [first],
            children: [first.id: [second], second.id: [backEdge]],
            expanded: [first.id, second.id]
        )

        #expect(rows.map(\.id) == [first.id, second.id])
        #expect(rows.map(\.depth) == [0, 1])
    }

    @Test func largeFlatInputKeepsEveryRowInStableOrder() {
        let entries = (0..<10_000).map { entry(String(format: "note-%05d.md", $0), directory: false) }

        let rows = FileTreeProjection.rows(roots: entries, children: [:], expanded: [])

        #expect(rows.count == entries.count)
        #expect(rows.first?.entry == entries.first)
        #expect(rows.last?.entry == entries.last)
        #expect(rows.map(\.depth).allSatisfy { $0 == 0 })
    }
}
