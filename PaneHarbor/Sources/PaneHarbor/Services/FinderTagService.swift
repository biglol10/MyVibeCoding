import Foundation

public protocol FinderTagServicing: Sendable {
    func tags(for url: URL) throws -> [FinderTag]
    func setTags(_ tags: [FinderTag], for url: URL) throws
}

public struct FinderTagService: FinderTagServicing, Sendable {
    public init() {}

    public func tags(for url: URL) throws -> [FinderTag] {
        let values = try url.resourceValues(forKeys: [URLResourceKey.tagNamesKey])
        return FinderTag.normalized(values.tagNames ?? [])
    }

    public func setTags(_ tags: [FinderTag], for url: URL) throws {
        try (url as NSURL).setResourceValue(
            FinderTag.normalized(tags.map(\.name)).map(\.name),
            forKey: URLResourceKey.tagNamesKey
        )
    }
}
