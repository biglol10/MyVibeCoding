import Foundation

public struct SidebarFavorite: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL
    public var systemImageName: String

    public init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        systemImageName: String = "folder"
    ) {
        self.id = id
        self.title = title
        self.url = url.standardizedFileURL
        self.systemImageName = systemImageName
    }
}

public struct SidebarFavoriteItem: Equatable, Identifiable, Sendable {
    public var favorite: SidebarFavorite
    public var isMissing: Bool

    public init(favorite: SidebarFavorite, isMissing: Bool) {
        self.favorite = favorite
        self.isMissing = isMissing
    }

    public var id: UUID { favorite.id }
}

public struct SidebarRecentFolder: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var url: URL
    public var title: String

    public init(url: URL, title: String? = nil) {
        let standardizedURL = url.standardizedFileURL
        self.url = standardizedURL
        self.title = title ?? standardizedURL.lastPathComponent
    }

    public var id: String { url.path }
}

public struct SidebarState: Codable, Equatable, Sendable {
    public var favorites: [SidebarFavorite]
    public var recentFolders: [SidebarRecentFolder]

    public init(
        favorites: [SidebarFavorite] = SidebarState.defaultFavorites(),
        recentFolders: [SidebarRecentFolder] = []
    ) {
        self.favorites = favorites
        self.recentFolders = recentFolders
    }

    public static func defaultFavorites(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [SidebarFavorite] {
        [
            SidebarFavorite(title: "Home", url: homeDirectory, systemImageName: "house"),
            SidebarFavorite(
                title: "Desktop",
                url: homeDirectory.appendingPathComponent("Desktop", isDirectory: true),
                systemImageName: "desktopcomputer"
            ),
            SidebarFavorite(
                title: "Documents",
                url: homeDirectory.appendingPathComponent("Documents", isDirectory: true),
                systemImageName: "doc"
            ),
            SidebarFavorite(
                title: "Downloads",
                url: homeDirectory.appendingPathComponent("Downloads", isDirectory: true),
                systemImageName: "arrow.down.circle"
            ),
            SidebarFavorite(
                title: "Applications",
                url: URL(fileURLWithPath: "/Applications", isDirectory: true),
                systemImageName: "a.square"
            )
        ]
    }
}
