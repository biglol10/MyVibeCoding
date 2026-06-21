import Foundation

public struct AppDiscoveryService: Sendable {
    private let searchRoots: [URL]
    private let metadataReader: AppMetadataReader

    public init(
        searchRoots: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ],
        metadataReader: AppMetadataReader = AppMetadataReader()
    ) {
        self.searchRoots = searchRoots
        self.metadataReader = metadataReader
    }

    public func discoverApps() async throws -> [InstalledApp] {
        var apps: [InstalledApp] = []
        for root in searchRoots where FileManager.default.fileExists(atPath: root.path) {
            let contents = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for url in contents where url.pathExtension == "app" {
                if let app = try? metadataReader.readApp(at: url), !isProtectedSystemApp(app) {
                    apps.append(app)
                }
            }
        }
        return apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func isProtectedSystemApp(_ app: InstalledApp) -> Bool {
        app.bundleURL.path.hasPrefix("/System/Applications/")
    }
}
