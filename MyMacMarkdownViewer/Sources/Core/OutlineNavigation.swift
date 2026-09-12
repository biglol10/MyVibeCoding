import Foundation

public struct OutlineEntry: Identifiable, Equatable, Sendable {
    public var title: String
    public var level: Int
    public var from: Int
    public var id: Int { from }
    public init(title: String, level: Int, from: Int) {
        self.title = title; self.level = level; self.from = from
    }
}

public struct OutlineNavigation: Sendable {
    public struct Row: Identifiable, Equatable, Sendable {
        public let entry: OutlineEntry
        public let depth: Int
        public let hasChildren: Bool
        public var id: Int { entry.id }
    }
    public let rows: [Row]
    private let parents: [Int?]
    private let searchTitles: [String]
    public let collapsibleIDs: Set<Int>

    public init(_ entries: [OutlineEntry]) {
        var stack: [Int] = [], parents: [Int?] = [], depths: [Int] = []
        var branches = Set<Int>()
        for (index, entry) in entries.enumerated() {
            while let last = stack.last, entries[last].level >= entry.level { stack.removeLast() }
            parents.append(stack.last)
            depths.append(stack.count)
            if let parent = stack.last { branches.insert(parent) }
            stack.append(index)
        }
        self.parents = parents
        self.collapsibleIDs = Set(branches.map { entries[$0].id })
        self.rows = entries.enumerated().map { index, entry in
            Row(entry: entry, depth: depths[index], hasChildren: branches.contains(index))
        }
        self.searchTitles = entries.map { Self.normalized($0.title) }
    }

    public static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping.lowercased()
    }

    public func firstMatch(_ query: String) -> OutlineEntry? {
        let value = Self.normalized(query)
        guard !value.isEmpty, let index = searchTitles.firstIndex(where: { $0.contains(value) }) else { return nil }
        return rows[index].entry
    }

    public func visibleRows(query: String, collapsed: Set<Int>) -> [Row] {
        let value = Self.normalized(query)
        if !value.isEmpty {
            var included = Set<Int>()
            for index in rows.indices where searchTitles[index].contains(value) {
                var current: Int? = index
                while let item = current {
                    if !included.insert(item).inserted { break }
                    current = parents[item]
                }
            }
            return rows.enumerated().compactMap { included.contains($0.offset) ? $0.element : nil }
        }
        var hidden = Set<Int>()
        return rows.enumerated().compactMap { index, row in
            if let parent = parents[index], hidden.contains(parent) || collapsed.contains(rows[parent].id) {
                hidden.insert(index); return nil
            }
            return row
        }
    }
}
