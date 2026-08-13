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
        await discoverAppsWithCoverage().value
    }

    public func discoverAppsWithCoverage() async -> ScanResult<[InstalledApp]> {
        await Task.detached(priority: .userInitiated) {
            discoverAppsSynchronouslyWithCoverage()
        }.value
    }

    private func discoverAppsSynchronouslyWithCoverage() -> ScanResult<[InstalledApp]> {
        var apps: [InstalledApp] = []
        var issues: [ScanIssue] = []
        for root in searchRoots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles],
                errorHandler: { url, error in
                    issues.append(ScanIssue.from(path: url, error: error))
                    return true
                }
            ) else {
                continue
            }

            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                enumerator.skipDescendants()
                do {
                    let app = try metadataReader.readApp(at: url)
                    if !isProtectedSystemApp(app) {
                        apps.append(app)
                    }
                } catch {
                    issues.append(ScanIssue.from(path: url, error: error))
                }
            }
        }

        var seenPaths: Set<String> = []
        let uniqueApps = apps.filter { app in
            seenPaths.insert(app.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path).inserted
        }
        return ScanResult(
            value: uniqueApps.sorted {
                let nameOrder = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                if nameOrder == .orderedSame { return $0.bundleURL.path < $1.bundleURL.path }
                return nameOrder == .orderedAscending
            },
            issues: issues.deduplicatedAndSorted()
        )
    }

    private func isProtectedSystemApp(_ app: InstalledApp) -> Bool {
        app.bundleURL.path.hasPrefix("/System/Applications/")
    }
}
