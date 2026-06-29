import Foundation

public protocol SidebarFavoritesStoring: AnyObject {
    func load() -> SidebarState
    func save(_ state: SidebarState)
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

    public func load() -> SidebarState {
        guard let data = defaults.data(forKey: key) else {
            return SidebarState()
        }

        do {
            return try JSONDecoder().decode(SidebarState.self, from: data)
        } catch {
            return SidebarState()
        }
    }

    public func save(_ state: SidebarState) {
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
