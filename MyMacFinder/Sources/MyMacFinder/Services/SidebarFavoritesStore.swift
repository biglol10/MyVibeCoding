import Foundation

public protocol SidebarFavoritesStoring: AnyObject {
    func load() throws -> SidebarState
    func save(_ state: SidebarState) throws
    func reset() throws
}

public extension SidebarFavoritesStoring {
    func reset() throws {}
}

public final class UserDefaultsSidebarFavoritesStore: SidebarFavoritesStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "MyMacFinder.SidebarState"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> SidebarState {
        guard let data = defaults.data(forKey: key) else {
            return SidebarState()
        }

        return try JSONDecoder().decode(SidebarState.self, from: data)
    }

    public func save(_ state: SidebarState) throws {
        let data = try JSONEncoder().encode(state)
        defaults.set(data, forKey: key)
    }

    public func reset() throws {
        defaults.removeObject(forKey: key)
    }
}
