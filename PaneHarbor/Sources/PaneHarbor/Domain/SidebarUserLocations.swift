import Darwin
import Foundation

/// Resolve shortcut destinations without reading them or granting file access.
/// In a sandbox, homeDirectoryForCurrentUser points at the app's container.
public enum SidebarUserLocations {
    public static var homeDirectory: URL {
        var capacity = 4_096
        while capacity <= 1_048_576 {
            var buffer = [CChar](repeating: 0, count: capacity)
            var record = passwd()
            var result: UnsafeMutablePointer<passwd>?
            var status: Int32 = 0
            let home: String? = buffer.withUnsafeMutableBufferPointer { storage in
                status = getpwuid_r(getuid(), &record, storage.baseAddress, storage.count, &result)
                guard status == 0, result != nil, let directory = record.pw_dir else { return nil }
                return String(cString: directory)
            }
            if let home, home.hasPrefix("/"), !home.isEmpty {
                return URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL
            }
            guard status == ERANGE else { break }
            capacity *= 2
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}

extension SidebarState {
    /// Repair only the previous built-in container shortcuts. Custom favorites,
    /// their order, and their identifiers stay intact.
    public static func repairContainerDefaults(
        _ state: SidebarState,
        sandboxed: Bool,
        containerHome: URL = FileManager.default.homeDirectoryForCurrentUser,
        userHome: URL = SidebarUserLocations.homeDirectory
    ) -> SidebarState {
        guard sandboxed, containerHome.standardizedFileURL.path != userHome.standardizedFileURL.path else { return state }
        let replacements = zip(defaultFavorites(homeDirectory: containerHome), defaultFavorites(homeDirectory: userHome))
        let pairs = Array(replacements)
        var repaired = state
        repaired.favorites = state.favorites.map { favorite in
            guard let pair = pairs.first(where: {
                $0.0.title == favorite.title && $0.0.systemImageName == favorite.systemImageName
                    && $0.0.url.path == favorite.url.path && $0.0.url.path != $0.1.url.path
            }) else { return favorite }
            var updated = favorite
            updated.url = pair.1.url
            return updated
        }
        return repaired
    }
}
