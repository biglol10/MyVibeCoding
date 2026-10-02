import Foundation

public struct FinderTag: Codable, Hashable, Comparable, Identifiable, Sendable {
    public var name: String
    public var id: String { name.lowercased() }

    public init(_ name: String) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalized(_ names: [String]) -> [FinderTag] {
        var seen = Set<String>()
        return names.compactMap { rawName in
            let tag = FinderTag(rawName)
            guard !tag.name.isEmpty else {
                return nil
            }
            guard seen.insert(tag.id).inserted else {
                return nil
            }
            return tag
        }
        .sorted()
    }

    public static func < (lhs: FinderTag, rhs: FinderTag) -> Bool {
        lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
