import Foundation

public struct RelatedFileScanner: Sendable {
    private let homeDirectory: URL
    private let extraScanRoots: [URL]
    private let matcher: CandidateMatcher
    private let protectionPolicy: ProtectionPolicy
    private let sizeCalculator: FileSizeCalculator
    private let safetyScorer: SafetyScorer

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        extraScanRoots: [URL] = [],
        matcher: CandidateMatcher = CandidateMatcher(),
        protectionPolicy: ProtectionPolicy? = nil,
        sizeCalculator: FileSizeCalculator = FileSizeCalculator(),
        safetyScorer: SafetyScorer = SafetyScorer()
    ) {
        self.homeDirectory = homeDirectory
        self.extraScanRoots = extraScanRoots
        self.matcher = matcher
        self.protectionPolicy = protectionPolicy ?? ProtectionPolicy(homeDirectory: homeDirectory)
        self.sizeCalculator = sizeCalculator
        self.safetyScorer = safetyScorer
    }

    public func scanRelatedFiles(for app: InstalledApp) async throws -> [RelatedFileCandidate] {
        let appBundleEvidence = MatchEvidence(
            type: .selectedAppBundle,
            matchedValue: app.displayName,
            sourcePath: app.bundleURL.path,
            strength: .strong
        )
        let appBundleProtected = protectionPolicy.isProtected(app.bundleURL)
        let appBundleSafety = safetyScorer.score(
            evidence: [appBundleEvidence],
            kind: .appBundle,
            isProtected: appBundleProtected,
            isKnownCleanupRoot: true
        )
        var candidates: [RelatedFileCandidate] = [
            RelatedFileCandidate(
                url: app.bundleURL,
                kind: .appBundle,
                size: app.bundleSize,
                matchReason: "selected app bundle",
                confidence: .high,
                evidence: [appBundleEvidence],
                safety: appBundleSafety.level,
                defaultSelected: appBundleSafety.defaultSelected,
                requiresManualReview: appBundleSafety.requiresManualReview,
                isProtected: appBundleProtected
            )
        ]

        for (root, kind) in scanRoots() {
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let urls = try childURLs(in: root)
            for url in urls {
                guard let match = matcher.match(url: url, app: app, kind: kind) else { continue }
                let isProtected = protectionPolicy.isProtected(url)
                let safety = safetyScorer.score(
                    evidence: match.evidence,
                    kind: kind,
                    isProtected: isProtected,
                    isKnownCleanupRoot: kind != .unknown
                )
                candidates.append(
                    RelatedFileCandidate(
                        url: url,
                        kind: kind,
                        size: (try? sizeCalculator.sizeOfItem(at: url)) ?? 0,
                        matchReason: match.matchReason,
                        confidence: match.confidence,
                        evidence: match.evidence,
                        safety: safety.level,
                        defaultSelected: safety.defaultSelected,
                        requiresManualReview: safety.requiresManualReview,
                        isProtected: isProtected
                    )
                )
            }
        }

        return Array(Set(candidates.map(\.url))).compactMap { url in
            candidates.first { $0.url == url }
        }.sorted { $0.url.path < $1.url.path }
    }

    private func scanRoots() -> [(URL, RelatedFileKind)] {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        let known: [(String, RelatedFileKind)] = [
            ("Application Support", .applicationSupport),
            ("Application Support/Caches", .cache),
            ("Caches", .cache),
            ("Preferences", .preferences),
            ("Preferences/ByHost", .preferences),
            ("Saved Application State", .savedState),
            ("Containers", .container),
            ("Group Containers", .groupContainer),
            ("Logs", .log),
            ("HTTPStorages", .httpStorage),
            ("WebKit", .webKit),
            ("Application Scripts", .script),
            ("LaunchAgents", .launchAgent)
        ]
        return known.map { (library.appendingPathComponent($0.0, isDirectory: true), $0.1) }
            + extraScanRoots.map { ($0, .unknown) }
    }

    private func childURLs(in root: URL) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return contents.map { root.appendingPathComponent($0.lastPathComponent) }
    }
}
