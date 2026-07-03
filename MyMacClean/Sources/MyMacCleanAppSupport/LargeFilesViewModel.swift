import Foundation
import Observation
import MyMacCleanCore

@MainActor
@Observable
public final class LargeFilesViewModel {
    private let scanRoots: [URL]
    private let minimumSize: Int64
    private let planner: DeletionPlanner
    private let executor: DeletionExecutor
    private let verifier: DeletionVerifier
    private let receiptStore: DeletionReceiptStore

    public var candidates: [LargeFileCandidate] = []
    public var selectedCandidateIDs: Set<LargeFileCandidate.ID> = []
    public var searchText = ""
    public var sort: LargeFileSort = .sizeDescending
    public var isScanning = false
    public var isDeleting = false
    public var hasScanned = false
    public var errorMessage: String?
    public var deletionReport: DeletionReportViewModel?

    public init(
        scanRoots: [URL] = LargeFilesViewModel.defaultScanRoots(),
        minimumSize: Int64 = 500 * 1_024 * 1_024,
        planner: DeletionPlanner = DeletionPlanner(),
        executor: DeletionExecutor? = nil,
        verifier: DeletionVerifier = DeletionVerifier(),
        receiptStore: DeletionReceiptStore = .default()
    ) {
        self.scanRoots = scanRoots
        self.minimumSize = minimumSize
        self.planner = planner
        self.executor = executor ?? DeletionExecutor(
            deletionProtectionPolicy: UserFileCleanupPolicy(allowedRoots: scanRoots).deletionProtectionPolicy
        )
        self.verifier = verifier
        self.receiptStore = receiptStore
    }

    public static func defaultScanRoots(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
        ]
    }

    public var visibleCandidates: [LargeFileCandidate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = candidates.filter { candidate in
            query.isEmpty
                || candidate.url.lastPathComponent.lowercased().contains(query)
                || candidate.url.path.lowercased().contains(query)
                || candidate.kind.rawValue.lowercased().contains(query)
        }
        return sorted(filtered)
    }

    public var selectedCandidates: [LargeFileCandidate] {
        candidates.filter { selectedCandidateIDs.contains($0.id) }
    }

    public var selectedBytes: Int64 {
        selectedCandidates.reduce(0) { $0 + $1.size }
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
            candidates = try await LargeFileScanner(roots: scanRoots, minimumSize: minimumSize, recursive: false).scan()
            hasScanned = true
            errorMessage = nil
        } catch {
            hasScanned = true
            errorMessage = error.localizedDescription
        }
    }

    public func moveSelectedToTrash(confirmation: String) async {
        guard !isDeleting else { return }
        let relatedCandidates = selectedCandidates.map { candidate in
            RelatedFileCandidate(
                id: candidate.id,
                url: candidate.url,
                kind: .unknown,
                size: candidate.size,
                matchReason: "large file selected by user",
                confidence: .high,
                safety: .review,
                defaultSelected: false,
                requiresManualReview: true,
                isProtected: false
            )
        }
        let app = InstalledApp(
            displayName: "Large Files",
            bundleIdentifier: nil,
            version: nil,
            executableName: nil,
            bundleURL: scanRoots.first ?? FileManager.default.homeDirectoryForCurrentUser,
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
                appName: "Large Files",
                bundleIdentifier: nil,
                bundlePath: app.bundleURL.path,
                action: .largeFileCleanup,
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

    private func removeVerifiedDeletedCandidates(from verificationResults: [DeletionVerificationResult]) {
        let deletedPaths = Set(verificationResults.filter { $0.status == .deleted }.map(\.path))
        candidates.removeAll { deletedPaths.contains($0.url.path) }
        let remainingIDs = Set(candidates.map(\.id))
        selectedCandidateIDs.formIntersection(remainingIDs)
    }

    private func sorted(_ candidates: [LargeFileCandidate]) -> [LargeFileCandidate] {
        switch sort {
        case .sizeDescending:
            candidates.sorted {
                if $0.size == $1.size {
                    return $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
                }
                return $0.size > $1.size
            }
        case .modifiedDescending:
            candidates.sorted {
                ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast)
            }
        case .pathAscending:
            candidates.sorted {
                $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
            }
        }
    }
}
