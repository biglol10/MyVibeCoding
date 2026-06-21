import Foundation
import Observation
import MyMacCleanCore

@MainActor
@Observable
public final class ApplicationListViewModel {
    private let discoveryService: AppDiscoveryService
    private let scanner: RelatedFileScanner
    private let planner: DeletionPlanner
    private let executor: DeletionExecutor
    private let verifier: DeletionVerifier
    private let receiptStore: DeletionReceiptStore

    public var apps: [InstalledApp] = []
    public var selectedApp: InstalledApp?
    public var candidates: [RelatedFileCandidate] = []
    public var selectedCandidateIDs: Set<RelatedFileCandidate.ID> = []
    public var deletionResults: [DeletionItemResult] = []
    public var deletionReport: DeletionReportViewModel?
    public var errorMessage: String?
    public var isScanning = false

    public init(
        discoveryService: AppDiscoveryService = AppDiscoveryService(),
        scanner: RelatedFileScanner = RelatedFileScanner(),
        planner: DeletionPlanner = DeletionPlanner(),
        executor: DeletionExecutor = DeletionExecutor(),
        verifier: DeletionVerifier = DeletionVerifier(),
        receiptStore: DeletionReceiptStore = DeletionReceiptStore(
            fileURL: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/MyMacClean/deletion-receipts.jsonl")
        )
    ) {
        self.discoveryService = discoveryService
        self.scanner = scanner
        self.planner = planner
        self.executor = executor
        self.verifier = verifier
        self.receiptStore = receiptStore
    }

    public func loadApps() async {
        do {
            apps = try await discoveryService.discoverApps()
            selectApp(apps.first)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func selectApp(id: InstalledApp.ID?) {
        selectApp(apps.first { $0.id == id })
    }

    public func selectApp(_ app: InstalledApp?) {
        guard selectedApp?.id != app?.id else { return }
        selectedApp = app
        candidates = []
        selectedCandidateIDs = []
        deletionResults = []
        deletionReport = nil
    }

    public func scanSelectedApp() async {
        guard let selectedApp else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            candidates = try await scanner.scanRelatedFiles(for: selectedApp)
            selectedCandidateIDs = Set(candidates.filter(\.defaultSelected).map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func makePlan() throws -> DeletionPlan {
        guard let selectedApp else { throw DeletionPlannerError.emptySelection }
        return try planner.makePlan(app: selectedApp, candidates: candidates, selectedIDs: selectedCandidateIDs)
    }

    public func deleteConfirmedItems(confirmation: String) async {
        do {
            let plan = try makePlan()
            let results = await executor.execute(plan: plan, confirmation: confirmation)
            let verificationResults = await verifier.verify(plan: plan)
            let receipt = DeletionReceipt(
                appName: plan.app.displayName,
                bundleIdentifier: plan.app.bundleIdentifier,
                bundlePath: plan.app.bundleURL.path,
                action: .uninstall,
                selectedCandidates: plan.candidates.map {
                    DeletionReceiptCandidate(path: $0.url.path, kind: $0.kind, size: $0.size, safety: $0.safety, evidence: $0.evidence)
                },
                executionResults: results,
                verificationResults: verificationResults,
                confirmationMatched: results.allSatisfy { $0.errorMessage != "confirmation phrase mismatch" }
            )
            try? receiptStore.append(receipt)
            deletionResults = results
            reconcileSuccessfulDeletion(plan: plan, results: results)
            deletionReport = DeletionReportViewModel(receipt: receipt)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reconcileSuccessfulDeletion(plan: DeletionPlan, results: [DeletionItemResult]) {
        guard results.allSatisfy(\.success) else { return }

        let deletedCandidateIDs = Set(plan.candidates.map(\.id))
        let removedAppBundle = plan.candidates.contains {
            $0.kind == .appBundle && $0.url == plan.app.bundleURL
        }

        if removedAppBundle {
            removeDeletedAppFromList(plan.app)
        } else {
            candidates.removeAll { deletedCandidateIDs.contains($0.id) }
            selectedCandidateIDs.subtract(deletedCandidateIDs)
        }
    }

    private func removeDeletedAppFromList(_ deletedApp: InstalledApp) {
        let deletedIndex = apps.firstIndex { $0.id == deletedApp.id }
        apps.removeAll { $0.id == deletedApp.id }

        guard !apps.isEmpty else {
            selectedApp = nil
            candidates = []
            selectedCandidateIDs = []
            deletionResults = []
            return
        }

        let replacementIndex = min(deletedIndex ?? 0, apps.count - 1)
        selectApp(apps[replacementIndex])
    }
}
