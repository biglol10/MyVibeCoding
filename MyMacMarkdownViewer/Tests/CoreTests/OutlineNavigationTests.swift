import Foundation
import Testing
@testable import MyMarkdownCore

struct OutlineNavigationTests {
    private let entries = [
        OutlineEntry(title: "안내", level: 1, from: 0),
        OutlineEntry(title: "준비", level: 3, from: 20),
        OutlineEntry(title: "한글 Search", level: 5, from: 40),
        OutlineEntry(title: "설치", level: 2, from: 60),
        OutlineEntry(title: "다음", level: 1, from: 80),
        OutlineEntry(title: "한글 Search", level: 2, from: 100)
    ]
    @Test func skippedLevelsUseActualAncestors() {
        let tree = OutlineNavigation(entries)
        #expect(tree.rows.map(\.depth) == [0, 1, 2, 1, 0, 1])
        #expect(tree.collapsibleIDs == [0, 20, 80])
        #expect(tree.visibleRows(query: "", collapsed: [20]).map(\.id) == [0, 20, 60, 80, 100])
        #expect(tree.visibleRows(query: "", collapsed: [0, 80]).map(\.id) == [0, 80])
    }
    @Test func searchRevealsCollapsedMatchesAndOnlyTheirAncestors() {
        let tree = OutlineNavigation(entries)
        #expect(tree.visibleRows(query: "  SEARCH \n", collapsed: [0, 20, 80]).map(\.id) == [0, 20, 40, 80, 100])
        #expect(tree.visibleRows(query: "준비", collapsed: []).map(\.id) == [0, 20])
        #expect(tree.firstMatch("Search")?.from == 40)
    }
    @Test func canonicalKoreanAndEmptyResults() {
        let tree = OutlineNavigation(entries)
        #expect(tree.visibleRows(query: "한글".decomposedStringWithCanonicalMapping, collapsed: []).map(\.id) == [0, 20, 40, 80, 100])
        #expect(tree.visibleRows(query: "없는 항목", collapsed: []).isEmpty)
        #expect(tree.firstMatch("   ") == nil)
        #expect(OutlineNavigation([]).visibleRows(query: "", collapsed: []).isEmpty)
    }
    @Test func clearingSearchRestoresCollapsedHierarchyWithoutChangingSourceEntries() {
        let tree = OutlineNavigation(entries)
        _ = tree.visibleRows(query: "한글", collapsed: [0])
        #expect(tree.visibleRows(query: "", collapsed: [0]).map(\.id) == [0, 80, 100])
        #expect(tree.rows.map(\.entry) == entries)
        #expect(tree.visibleRows(query: "", collapsed: [999]).count == entries.count)
    }
}
