import Foundation

public protocol SecurityScopedBookmarkStoring: AnyObject {
    func load() -> [FolderAccessGrant]
    func save(_ grant: FolderAccessGrant) throws
    func remove(id: FolderAccessGrantID)
    func reset()
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

    public func load() -> [FolderAccessGrant] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }
        return (try? JSONDecoder().decode([FolderAccessGrant].self, from: data)) ?? []
    }

    public func save(_ grant: FolderAccessGrant) throws {
        var grants = load()
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

    public func remove(id: FolderAccessGrantID) {
        let grants = load().filter { $0.id != id }
        guard let data = try? JSONEncoder().encode(grants) else {
            return
        }
        defaults.set(data, forKey: key)
    }

    public func reset() {
        defaults.removeObject(forKey: key)
    }
}
