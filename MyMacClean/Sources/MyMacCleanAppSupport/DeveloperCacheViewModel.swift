import Foundation
import Observation
import MyMacCleanCore

@MainActor
@Observable
public final class DeveloperCacheViewModel {
    private let homeDirectory: URL
    private let dockerStorageURL: URL?
    private let planner: DeletionPlanner
    private let executor: DeletionExecutor
    private let verifier: DeletionVerifier
    private let receiptStore: DeletionReceiptStore

    public var candidates: [DeveloperCacheCandidate] = []
    public var selectedCandidateIDs: Set<DeveloperCacheCandidate.ID> = []
    public var searchText = ""
    public var sort: DeveloperCacheSort = .tool
    public var isScanning = false
    public var isDeleting = false
    public var hasScanned = false
    public var errorMessage: String?
    public var deletionReport: DeletionReportViewModel?

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        dockerStorageURL: URL? = nil,
        planner: DeletionPlanner = DeletionPlanner(),
        executor: DeletionExecutor? = nil,
        verifier: DeletionVerifier = DeletionVerifier(),
        receiptStore: DeletionReceiptStore = .default()
    ) {
        self.homeDirectory = homeDirectory
        self.dockerStorageURL = dockerStorageURL ?? Self.defaultDockerStorageURL(homeDirectory: homeDirectory)
        self.planner = planner
        self.executor = executor ?? DeletionExecutor(
            deletionProtectionPolicy: UserFileCleanupPolicy(allowedRoots: Self.deletableRoots(homeDirectory: homeDirectory)).deletionProtectionPolicy
        )
        self.verifier = verifier
        self.receiptStore = receiptStore
    }

    public static func defaultDockerStorageURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory.appendingPathComponent("Library/Containers/com.docker.docker/Data", isDirectory: true)
    }

    public static func deletableRoots(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            "Library/Developer/Xcode/DerivedData",
            "Library/Developer/Xcode/Archives",
            "Library/Developer/Xcode/iOS DeviceSupport",
            "Library/Caches/org.swift.swiftpm",
            ".npm",
            "Library/Caches/Yarn",
            "Library/pnpm/store",
            "Library/Caches/CocoaPods",
            ".gradle/caches"
        ].map { homeDirectory.appendingPathComponent($0, isDirectory: true) }
    }

    public var visibleCandidates: [DeveloperCacheCandidate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = candidates.filter { candidate in
            query.isEmpty
                || candidate.tool.title.lowercased().contains(query)
                || candidate.tool.groupTitle.lowercased().contains(query)
                || candidate.url.path.lowercased().contains(query)
                || candidate.safety.rawValue.lowercased().contains(query)
        }
        return sorted(filtered)
    }

    public var selectedCandidates: [DeveloperCacheCandidate] {
        candidates.filter { selectedCandidateIDs.contains($0.id) && $0.isDeletable }
    }

    public var selectedBytes: Int64 {
        selectedCandidates.reduce(0) { $0 + $1.size }
    }

    public var selectedRelatedCandidates: [RelatedFileCandidate] {
        selectedCandidates.map(Self.relatedCandidate(for:))
    }

    public var totalBytes: Int64 {
        candidates.reduce(0) { $0 + $1.size }
    }

    public func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        candidates = []
        selectedCandidateIDs = []
        deletionReport = nil
        do {
            candidates = try await DeveloperCacheScanner(
                homeDirectory: homeDirectory,
                dockerStorageURL: dockerStorageURL
            ).scan()
            selectedCandidateIDs = Set(candidates.filter(\.defaultSelected).map(\.id))
            hasScanned = true
            errorMessage = nil
        } catch {
            hasScanned = true
            errorMessage = error.localizedDescription
        }
    }

    public func setCandidateSelection(_ id: DeveloperCacheCandidate.ID, isSelected: Bool) {
        guard let candidate = candidates.first(where: { $0.id == id }), candidate.isDeletable else {
            selectedCandidateIDs.remove(id)
            return
        }
        if isSelected {
            selectedCandidateIDs.insert(id)
        } else {
            selectedCandidateIDs.remove(id)
        }
    }

    public func moveSelectedToTrash(confirmation: String) async {
        guard !isDeleting else { return }
        let relatedCandidates = selectedRelatedCandidates
        guard !relatedCandidates.isEmpty else {
            deletionReport = nil
            errorMessage = "Select at least one deletable item."
            return
        }

        let app = InstalledApp(
            displayName: "Developer Cache",
            bundleIdentifier: nil,
            version: nil,
            executableName: nil,
            bundleURL: homeDirectory,
            iconIdentifier: nil,
            bundleSize: 0,
            lastOpenedAt: nil
        )

        do {
            let selectedIDs = Set(relatedCandidates.map(\.id))
            let plan = try planner.makePlan(app: app, candidates: relatedCandidates, selectedIDs: selectedIDs)
            isDeleting = true
            defer { isDeleting = false }
            let results = await executor.execute(plan: plan, confirmation: confirmation, mode: .moveToTrash)
            let verificationResults = await verifier.verify(plan: plan, executionResults: results)
            let receipt = DeletionReceipt(
                appName: "Developer Cache",
                bundleIdentifier: nil,
                bundlePath: app.bundleURL.path,
                action: .developerCacheCleanup,
                selectedCandidates: plan.candidates.map {
                    DeletionReceiptCandidate(path: $0.url.path, kind: $0.kind, size: $0.size, safety: $0.safety, evidence: $0.evidence)
                },
                executionResults: results,
                verificationResults: verificationResults,
                confirmationMatched: results.allSatisfy { $0.errorMessage != DeletionExecutionErrorMessage.confirmationMismatch }
            )
            deletionReport = DeletionReportViewModel(receipt: receipt)
            removeVerifiedDeletedCandidates(from: verificationResults)
            errorMessage = nil
            do {
                try receiptStore.append(receipt)
            } catch {
                errorMessage = "Cleanup finished, but deletion history could not be saved: \(error.localizedDescription)"
            }
        } catch {
            deletionReport = nil
            errorMessage = error.localizedDescription
            isDeleting = false
        }
    }

    private static func relatedCandidate(for candidate: DeveloperCacheCandidate) -> RelatedFileCandidate {
        RelatedFileCandidate(
            id: candidate.id,
            url: candidate.url,
            kind: .cache,
            size: candidate.size,
            matchReason: "\(candidate.tool.title) selected by user",
            confidence: .high,
            safety: candidate.safety == .safe ? .safe : .review,
            defaultSelected: candidate.defaultSelected,
            requiresManualReview: candidate.safety != .safe,
            isProtected: !candidate.isDeletable
        )
    }

    private func removeVerifiedDeletedCandidates(from verificationResults: [DeletionVerificationResult]) {
        let deletedPaths = Set(verificationResults.filter { $0.status == .deleted }.map(\.path))
        candidates.removeAll { deletedPaths.contains($0.url.path) }
        let remainingIDs = Set(candidates.map(\.id))
        selectedCandidateIDs.formIntersection(remainingIDs)
    }

    private func sorted(_ candidates: [DeveloperCacheCandidate]) -> [DeveloperCacheCandidate] {
        switch sort {
        case .tool:
            candidates.sorted { lhs, rhs in
                let lhsIndex = DeveloperCacheTool.allCases.firstIndex(of: lhs.tool) ?? .max
                let rhsIndex = DeveloperCacheTool.allCases.firstIndex(of: rhs.tool) ?? .max
                if lhsIndex == rhsIndex {
                    return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
                }
                return lhsIndex < rhsIndex
            }
        case .sizeDescending:
            candidates.sorted {
                if $0.size == $1.size {
                    return $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
                }
                return $0.size > $1.size
            }
        case .safety:
            candidates.sorted { lhs, rhs in
                let lhsIndex = DeveloperCacheSafety.allCases.firstIndex(of: lhs.safety) ?? .max
                let rhsIndex = DeveloperCacheSafety.allCases.firstIndex(of: rhs.safety) ?? .max
                if lhsIndex == rhsIndex {
                    return lhs.tool.title.localizedStandardCompare(rhs.tool.title) == .orderedAscending
                }
                return lhsIndex < rhsIndex
            }
        }
    }
}
