import Foundation
import Observation
import MyMacCleanCore

@MainActor
@Observable
public final class OrphanFilesViewModel {
    private let homeDirectory: URL
    private var installedApps: [InstalledApp]
    private let orphanFileScanning: OrphanFileScanning
    private let planner: DeletionPlanner
    private let executor: DeletionExecutor
    private let verifier: DeletionVerifier
    private let receiptStore: DeletionReceiptStore

    public var groups: [OrphanFileGroup] = []
    public var selectedCandidateIDs: Set<RelatedFileCandidate.ID> = []
    public var deletionReport: DeletionReportViewModel?
    public var errorMessage: String?
    public var scanIssues: [ScanIssue] = []
    public var hasScanned = false
    public var isScanning = false
    public var isDeleting = false

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        installedApps: [InstalledApp],
        excludedBundleIdentifiers: [String] = Bundle.main.bundleIdentifier.map { [$0] } ?? [],
        planner: DeletionPlanner = DeletionPlanner(),
        executor: DeletionExecutor = DeletionExecutor(),
        verifier: DeletionVerifier = DeletionVerifier(),
        receiptStore: DeletionReceiptStore = .default(),
        orphanFileScanning: OrphanFileScanning? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.installedApps = installedApps
        self.orphanFileScanning = orphanFileScanning ?? .live(
            homeDirectory: homeDirectory,
            excludedBundleIdentifiers: excludedBundleIdentifiers
        )
        self.planner = planner
        self.executor = executor
        self.verifier = verifier
        self.receiptStore = receiptStore
    }

    public func loadGroups() async {
        isScanning = true
        defer { isScanning = false }
        groups = []
        selectedCandidateIDs = []
        deletionReport = nil
        scanIssues = []
        let result = await orphanFileScanning.scan(installedApps)
        groups = result.value
        scanIssues = result.issues
        selectedCandidateIDs = Set(groups.flatMap(\.candidates).filter(\.defaultSelected).map(\.id))
        hasScanned = true
        errorMessage = nil
    }

    public func updateInstalledApps(_ installedApps: [InstalledApp]) {
        self.installedApps = installedApps
        invalidateScanResults()
    }

    public var selectedCandidates: [RelatedFileCandidate] {
        groups.flatMap(\.candidates).filter { selectedCandidateIDs.contains($0.id) }
    }

    public var selectedBytes: Int64 {
        selectedCandidates.reduce(Int64(0)) { $0 + $1.size }
    }

    public func setGroupSelection(_ groupID: OrphanFileGroup.ID, isSelected: Bool) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        let groupCandidateIDs = Set(group.candidates.map(\.id))
        if isSelected {
            let selectableIDs = Set(group.candidates.filter { !$0.isProtected }.map(\.id))
            selectedCandidateIDs.formUnion(selectableIDs)
        } else {
            selectedCandidateIDs.subtract(groupCandidateIDs)
        }
    }

    public func isGroupFullySelected(_ group: OrphanFileGroup) -> Bool {
        let selectableIDs = group.candidates.filter { !$0.isProtected }.map(\.id)
        guard !selectableIDs.isEmpty else { return false }
        return selectableIDs.allSatisfy { selectedCandidateIDs.contains($0) }
    }

    public func groupSelectionSummary(for group: OrphanFileGroup) -> String {
        let selectedCount = group.candidates.filter { selectedCandidateIDs.contains($0.id) }.count
        return "\(selectedCount) of \(group.candidates.count) selected"
    }

    @discardableResult
    public func deleteSelectedLeftovers(
        confirmation: String,
        force: Bool = false,
        mode: DeletionMode = .moveToTrash
    ) async -> DeletionReportViewModel? {
        guard !isDeleting else { return nil }
        let app = InstalledApp(
            displayName: "Orphan Files",
            bundleIdentifier: nil,
            version: nil,
            executableName: nil,
            bundleURL: homeDirectory,
            iconIdentifier: nil,
            bundleSize: 0,
            lastOpenedAt: nil
        )
        let plan: DeletionPlan
        do {
            plan = try planner.makePlan(
                app: app,
                candidates: groups.flatMap(\.candidates),
                selectedIDs: selectedCandidateIDs
            )
        } catch {
            deletionReport = nil
            errorMessage = error.localizedDescription
            return nil
        }

        isDeleting = true
        defer { isDeleting = false }

        let candidates = plan.candidates
        let results = await executor.execute(plan: plan, confirmation: confirmation, force: force, mode: mode)
        let verificationResults = await verifier.verify(plan: plan, executionResults: results)
        let receipt = DeletionReceipt(
            appName: "Orphan Files",
            bundleIdentifier: nil,
            bundlePath: homeDirectory.path,
            action: .orphanCleanup,
            selectedCandidates: candidates.map {
                DeletionReceiptCandidate(path: $0.url.path, kind: $0.kind, size: $0.size, safety: $0.safety, evidence: $0.evidence)
            },
            executionResults: results,
            verificationResults: verificationResults,
            confirmationMatched: results.allSatisfy { $0.errorMessage != DeletionExecutionErrorMessage.confirmationMismatch }
        )

        do {
            try receiptStore.append(receipt)
            errorMessage = nil
        } catch {
            errorMessage = "Could not save deletion history: \(error.localizedDescription)"
        }

        let report = DeletionReportViewModel(receipt: receipt)
        deletionReport = report
        removeVerifiedDeletedCandidates(from: verificationResults)
        return report
    }

    private func removeVerifiedDeletedCandidates(from verificationResults: [DeletionVerificationResult]) {
        let deletedPaths = Set(verificationResults.filter { $0.status == .deleted }.map(\.path))
        guard !deletedPaths.isEmpty else { return }

        groups = groups.compactMap { group in
            let remainingCandidates = group.candidates.filter { !deletedPaths.contains($0.url.path) }
            guard !remainingCandidates.isEmpty else { return nil }
            return OrphanFileGroup(
                inferredName: group.inferredName,
                inferredIdentifier: group.inferredIdentifier,
                candidates: remainingCandidates
            )
        }
        let remainingIDs = Set(groups.flatMap(\.candidates).map(\.id))
        selectedCandidateIDs.formIntersection(remainingIDs)
    }

    private func invalidateScanResults() {
        groups = []
        selectedCandidateIDs = []
        deletionReport = nil
        scanIssues = []
        hasScanned = false
    }
}
