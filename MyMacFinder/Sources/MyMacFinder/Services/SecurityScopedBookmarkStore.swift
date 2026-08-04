import Foundation

public protocol SecurityScopedBookmarkStoring: AnyObject {
    func load() throws -> [FolderAccessGrant]
    func save(_ grant: FolderAccessGrant) throws
    func remove(id: FolderAccessGrantID) throws
    func reset()
}

public enum SecurityScopedBookmarkStoreError: LocalizedError, Equatable, Sendable {
    case corruptedData

    public var errorDescription: String? {
        switch self {
        case .corruptedData:
            return "Saved folder access data is damaged. It was preserved and was not overwritten."
        }
    }
}

public final class SecurityScopedBookmarkStore: SecurityScopedBookmarkStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "MyMacFinder.SecurityScopedBookmarks"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> [FolderAccessGrant] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }
        do {
            return try JSONDecoder().decode([FolderAccessGrant].self, from: data)
        } catch {
            throw SecurityScopedBookmarkStoreError.corruptedData
        }
    }

    public func save(_ grant: FolderAccessGrant) throws {
        var grants = try load()
        grants.removeAll { existing in
            existing.id == grant.id || existing.url.standardizedFileURL == grant.url.standardizedFileURL
        }
        grants.append(grant)
        grants.sort { lhs, rhs in
            lhs.displayPath.localizedStandardCompare(rhs.displayPath) == .orderedAscending
        }
        let data = try JSONEncoder().encode(grants)
        defaults.set(data, forKey: key)
    }

    public func remove(id: FolderAccessGrantID) throws {
        let grants = try load().filter { $0.id != id }
        let data = try JSONEncoder().encode(grants)
        defaults.set(data, forKey: key)
    }

    public func reset() {
        defaults.removeObject(forKey: key)
    }
}
