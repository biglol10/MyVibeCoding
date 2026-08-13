import Foundation
import MyMacCleanCore

public struct ApplicationDiscovering: Sendable {
    public let discover: @Sendable () async -> ScanResult<[InstalledApp]>

    public init(_ discover: @escaping @Sendable () async -> ScanResult<[InstalledApp]>) {
        self.discover = discover
    }

    public static func live(service: AppDiscoveryService = AppDiscoveryService()) -> ApplicationDiscovering {
        ApplicationDiscovering { await service.discoverAppsWithCoverage() }
    }
}

public struct RelatedFileScanning: Sendable {
    public let scan: @Sendable (InstalledApp) async -> ScanResult<[RelatedFileCandidate]>

    public init(_ scan: @escaping @Sendable (InstalledApp) async -> ScanResult<[RelatedFileCandidate]>) {
        self.scan = scan
    }

    public static func live(scanner: RelatedFileScanner = RelatedFileScanner()) -> RelatedFileScanning {
        RelatedFileScanning { app in await scanner.scanRelatedFilesWithCoverage(for: app) }
    }
}

public struct OrphanFileScanning: Sendable {
    public let scan: @Sendable ([InstalledApp]) async -> ScanResult<[OrphanFileGroup]>

    public init(_ scan: @escaping @Sendable ([InstalledApp]) async -> ScanResult<[OrphanFileGroup]>) {
        self.scan = scan
    }

    public static func live(
        homeDirectory: URL,
        excludedBundleIdentifiers: [String]
    ) -> OrphanFileScanning {
        OrphanFileScanning { installedApps in
            await OrphanFileScanner(
                homeDirectory: homeDirectory,
                installedApps: installedApps,
                excludedBundleIdentifiers: excludedBundleIdentifiers
            ).scanWithCoverage()
        }
    }
}

public struct LargeFileScanning: Sendable {
    public let scan: @Sendable ([URL], Int64, Bool) async -> ScanResult<[LargeFileCandidate]>

    public init(_ scan: @escaping @Sendable ([URL], Int64, Bool) async -> ScanResult<[LargeFileCandidate]>) {
        self.scan = scan
    }

    public static let live = LargeFileScanning { roots, minimumSize, recursive in
        await LargeFileScanner(
            roots: roots,
            minimumSize: minimumSize,
            recursive: recursive
        ).scanWithCoverage()
    }
}

public struct DeveloperCacheScanning: Sendable {
    public let scan: @Sendable () async -> ScanResult<[DeveloperCacheCandidate]>

    public init(_ scan: @escaping @Sendable () async -> ScanResult<[DeveloperCacheCandidate]>) {
        self.scan = scan
    }

    public static func live(
        homeDirectory: URL,
        dockerStorageURL: URL?
    ) -> DeveloperCacheScanning {
        DeveloperCacheScanning {
            await DeveloperCacheScanner(
                homeDirectory: homeDirectory,
                dockerStorageURL: dockerStorageURL
            ).scanWithCoverage()
        }
    }
}

public struct StartupItemScanning: Sendable {
    public let scan: @Sendable () async -> ScanResult<[StartupItem]>

    public init(_ scan: @escaping @Sendable () async -> ScanResult<[StartupItem]>) {
        self.scan = scan
    }

    public static func live(scanner: StartupItemScanner = StartupItemScanner()) -> StartupItemScanning {
        StartupItemScanning { await scanner.scanWithCoverage() }
    }
}
