import Foundation

public struct OrphanFileGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let inferredName: String
    public let inferredIdentifier: String
    public let candidates: [RelatedFileCandidate]
    public let totalSize: Int64

    public init(inferredName: String, inferredIdentifier: String, candidates: [RelatedFileCandidate]) {
        self.id = inferredIdentifier
        self.inferredName = inferredName
        self.inferredIdentifier = inferredIdentifier
        self.candidates = candidates
        self.totalSize = candidates.reduce(0) { $0 + $1.size }
    }
}

public struct OrphanFileScanner: Sendable {
    private let homeDirectory: URL
    private let installedApps: [InstalledApp]
    private let excludedBundleIdentifiers: Set<String>
    private let protectionPolicy: ProtectionPolicy
    private let sizeCalculator: FileSizeCalculator
    private let safetyScorer: SafetyScorer

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        installedApps: [InstalledApp],
        excludedBundleIdentifiers: [String] = [],
        protectionPolicy: ProtectionPolicy? = nil,
        sizeCalculator: FileSizeCalculator = FileSizeCalculator(),
        safetyScorer: SafetyScorer = SafetyScorer()
    ) {
        self.homeDirectory = homeDirectory
        self.installedApps = installedApps
        self.excludedBundleIdentifiers = Set(excludedBundleIdentifiers.map { $0.lowercased() })
        self.protectionPolicy = protectionPolicy ?? ProtectionPolicy(homeDirectory: homeDirectory)
        self.sizeCalculator = sizeCalculator
        self.safetyScorer = safetyScorer
    }

    public func scan() async throws -> [OrphanFileGroup] {
        let installedIdentifiers = Set(installedApps.compactMap { $0.bundleIdentifier?.lowercased() })
            .union(excludedBundleIdentifiers)
        var groupedCandidates: [String: [RelatedFileCandidate]] = [:]

        for (root, kind) in scanRoots() where FileManager.default.fileExists(atPath: root.path) {
            let urls = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ).map { root.appendingPathComponent($0.lastPathComponent) }

            for url in urls {
                guard let identifier = bundleIdentifierCandidate(from: url.lastPathComponent) else { continue }
                guard !isIgnoredSystemIdentifier(identifier) else { continue }
                guard !isRelatedToInstalledApp(identifier, installedIdentifiers: installedIdentifiers) else { continue }

                let evidence = MatchEvidence(
                    type: .bundleIdentifier,
                    matchedValue: identifier,
                    sourcePath: url.path,
                    strength: .strong
                )
                let isProtected = protectionPolicy.isProtected(url)
                let safety = safetyScorer.score(
                    evidence: [evidence],
                    kind: kind,
                    isProtected: isProtected,
                    isKnownCleanupRoot: true
                )
                let allowsDefaultSelection = allowsDefaultSelection(for: kind)
                let candidate = RelatedFileCandidate(
                    url: url,
                    kind: kind,
                    size: (try? sizeCalculator.sizeOfItem(at: url, recursive: false)) ?? 0,
                    matchReason: "orphan bundle identifier match",
                    confidence: .high,
                    evidence: [evidence],
                    safety: allowsDefaultSelection ? safety.level : .review,
                    defaultSelected: false,
                    requiresManualReview: true,
                    isProtected: isProtected
                )
                groupedCandidates[identifier, default: []].append(candidate)
            }
        }

        return groupedCandidates
            .map { identifier, candidates in
                OrphanFileGroup(
                    inferredName: identifier,
                    inferredIdentifier: identifier,
                    candidates: candidates.sorted { $0.url.path < $1.url.path }
                )
            }
            .sorted {
                $0.inferredIdentifier.localizedCaseInsensitiveCompare($1.inferredIdentifier) == .orderedAscending
            }
    }

    private func scanRoots() -> [(URL, RelatedFileKind)] {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        return [
            (library.appendingPathComponent("Application Support", isDirectory: true), .applicationSupport),
            (library.appendingPathComponent("Application Support/Caches", isDirectory: true), .cache),
            (library.appendingPathComponent("Caches", isDirectory: true), .cache),
            (library.appendingPathComponent("Preferences", isDirectory: true), .preferences),
            (library.appendingPathComponent("Preferences/ByHost", isDirectory: true), .preferences),
            (library.appendingPathComponent("Saved Application State", isDirectory: true), .savedState),
            (library.appendingPathComponent("HTTPStorages", isDirectory: true), .httpStorage),
            (library.appendingPathComponent("WebKit", isDirectory: true), .webKit),
            (library.appendingPathComponent("Logs", isDirectory: true), .log),
            (library.appendingPathComponent("LaunchAgents", isDirectory: true), .launchAgent)
        ]
    }

    private func bundleIdentifierCandidate(from lastPathComponent: String) -> String? {
        let stripped = lastPathComponent
            .replacingOccurrences(of: ".binarycookies", with: "")
            .replacingOccurrences(of: ".savedState", with: "")
            .replacingOccurrences(of: ".plist", with: "")
        let parts = stripped.split(separator: ".")
        guard parts.count >= 3 else { return nil }
        guard parts.allSatisfy({ part in
            part.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
        }) else {
            return nil
        }
        return parts.joined(separator: ".")
    }

    private func isIgnoredSystemIdentifier(_ identifier: String) -> Bool {
        let lowercased = identifier.lowercased()
        if lowercased.hasPrefix("com.apple.") || lowercased.contains(".com.apple.") {
            return true
        }
        return identifier.range(of: #"^[A-Z0-9]{10}\."#, options: .regularExpression) != nil
    }

    private func isRelatedToInstalledApp(_ identifier: String, installedIdentifiers: Set<String>) -> Bool {
        let lowercased = identifier.lowercased()
        return installedIdentifiers.contains { installedIdentifier in
            lowercased == installedIdentifier
                || lowercased.hasPrefix(installedIdentifier + ".")
                || installedIdentifier.hasPrefix(lowercased + ".")
        }
    }

    private func allowsDefaultSelection(for kind: RelatedFileKind) -> Bool {
        switch kind {
        case .cache, .preferences, .savedState, .httpStorage, .webKit, .log:
            true
        case .appBundle, .applicationSupport, .container, .groupContainer, .launchAgent, .launchDaemon, .script, .unknown:
            false
        }
    }
}
