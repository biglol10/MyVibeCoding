import Foundation

public struct DeveloperCacheScanner: Sendable {
    private struct Target: Sendable {
        let tool: DeveloperCacheTool
        let relativePath: String?
        let explicitURL: URL?
        let safety: DeveloperCacheSafety
        let explanation: String
    }

    private let homeDirectory: URL
    private let dockerStorageURL: URL?
    private let sizeCalculator: FileSizeCalculator

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        dockerStorageURL: URL? = nil,
        sizeCalculator: FileSizeCalculator = FileSizeCalculator()
    ) {
        self.homeDirectory = homeDirectory
        self.dockerStorageURL = dockerStorageURL
        self.sizeCalculator = sizeCalculator
    }

    public func scan() async throws -> [DeveloperCacheCandidate] {
        var candidates: [DeveloperCacheCandidate] = []
        for target in targets {
            let url = target.explicitURL ?? homeDirectory.appendingPathComponent(target.relativePath ?? "", isDirectory: true)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let size = (try? sizeCalculator.sizeOfItem(at: url)) ?? 0
            candidates.append(
                DeveloperCacheCandidate(
                    tool: target.tool,
                    url: url,
                    size: size,
                    safety: target.safety,
                    explanation: target.explanation
                )
            )
        }
        return candidates
    }

    private var targets: [Target] {
        var allTargets: [Target] = [
            Target(
                tool: .xcodeDerivedData,
                relativePath: "Library/Developer/Xcode/DerivedData",
                explicitURL: nil,
                safety: .safe,
                explanation: "Xcode will recreate DerivedData when projects build again. Close Xcode before deleting it during active builds."
            ),
            Target(
                tool: .xcodeArchives,
                relativePath: "Library/Developer/Xcode/Archives",
                explicitURL: nil,
                safety: .review,
                explanation: "Archives may be needed for release records or symbolication."
            ),
            Target(
                tool: .xcodeDeviceSupport,
                relativePath: "Library/Developer/Xcode/iOS DeviceSupport",
                explicitURL: nil,
                safety: .review,
                explanation: "DeviceSupport can be recreated, but deleting it may slow the next device connection."
            ),
            Target(
                tool: .swiftPackageManager,
                relativePath: "Library/Caches/org.swift.swiftpm",
                explicitURL: nil,
                safety: .safe,
                explanation: "SwiftPM cache contents are downloaded again when packages resolve."
            ),
            Target(
                tool: .npm,
                relativePath: ".npm",
                explicitURL: nil,
                safety: .safe,
                explanation: "npm cache contents are downloaded again during install."
            ),
            Target(
                tool: .yarn,
                relativePath: "Library/Caches/Yarn",
                explicitURL: nil,
                safety: .safe,
                explanation: "Yarn cache contents are downloaded again during install."
            ),
            Target(
                tool: .pnpm,
                relativePath: "Library/pnpm/store",
                explicitURL: nil,
                safety: .safe,
                explanation: "pnpm store packages can be restored during install."
            ),
            Target(
                tool: .cocoaPods,
                relativePath: "Library/Caches/CocoaPods",
                explicitURL: nil,
                safety: .review,
                explanation: "CocoaPods cache can be regenerated, but older project installs may take longer."
            ),
            Target(
                tool: .gradle,
                relativePath: ".gradle/caches",
                explicitURL: nil,
                safety: .review,
                explanation: "Gradle cache can be regenerated, but large projects may rebuild slowly afterward."
            )
        ]

        if let dockerStorageURL {
            allTargets.append(
                Target(
                    tool: .docker,
                    relativePath: nil,
                    explicitURL: dockerStorageURL,
                    safety: .readOnly,
                    explanation: "Docker storage is reported only. Cleanup should use Docker commands in this release."
                )
            )
        }

        return allTargets
    }
}
