import Foundation
import Observation
import MyMacCleanCore

public enum ApplicationListFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case userApplications
    case largeApplications

    public var id: Self { self }

    public var title: String {
        switch self {
        case .all: "All"
        case .userApplications: "User Apps"
        case .largeApplications: "Large"
        }
    }
}

public enum ApplicationListSort: String, CaseIterable, Identifiable, Sendable {
    case nameAscending
    case sizeDescending
    case pathAscending

    public var id: Self { self }

    public var title: String {
        switch self {
        case .nameAscending: "Name"
        case .sizeDescending: "Size"
        case .pathAscending: "Path"
        }
    }
}

@MainActor
@Observable
public final class ApplicationListViewModel {
    private let applicationDiscovering: ApplicationDiscovering
    private let excludedBundleIdentifiers: Set<String>
    private let excludedBundleURLs: [URL]
    private let relatedFileScanning: RelatedFileScanning
    private let planner: DeletionPlanner
    private let executor: DeletionExecutor
    private let verifier: DeletionVerifier
    private let runningApplicationMonitor: RunningApplicationMonitor
    private let receiptStore: DeletionReceiptStore

    public var apps: [InstalledApp] = [] {
        didSet { reconcileVisibleSelection() }
    }
    public var selectedApp: InstalledApp?
    public var candidates: [RelatedFileCandidate] = []
    public var selectedCandidateIDs: Set<RelatedFileCandidate.ID> = []
    public var deletionResults: [DeletionItemResult] = []
    public var deletionReport: DeletionReportViewModel?
    public var errorMessage: String?
    public var applicationDiscoveryIssues: [ScanIssue] = []
    public var relatedFileScanIssues: [ScanIssue] = []
    public var hasLoadedApps = false
    public var isLoadingApps = false
    public var isScanning = false
    public var isDeleting = false
    public var appSearchText = "" {
        didSet { reconcileVisibleSelection() }
    }
    public var appFilter: ApplicationListFilter = .all {
        didSet { reconcileVisibleSelection() }
    }
    public var appSort: ApplicationListSort = .nameAscending
    public var cleanupMode: ApplicationCleanupMode = .uninstall {
        didSet { reconcileCleanupModeSelection() }
    }

    public init(
        discoveryService: AppDiscoveryService = AppDiscoveryService(),
        excludedBundleIdentifiers: [String] = Bundle.main.bundleIdentifier.map { [$0] } ?? [],
        excludedBundleURLs: [URL] = [Bundle.main.bundleURL],
        scanner: RelatedFileScanner = RelatedFileScanner(),
        planner: DeletionPlanner = DeletionPlanner(),
        executor: DeletionExecutor = DeletionExecutor(),
        verifier: DeletionVerifier = DeletionVerifier(),
        runningApplicationMonitor: RunningApplicationMonitor = RunningApplicationMonitor(),
        receiptStore: DeletionReceiptStore = .default(),
        applicationDiscovering: ApplicationDiscovering? = nil,
        relatedFileScanning: RelatedFileScanning? = nil
    ) {
        self.applicationDiscovering = applicationDiscovering ?? .live(service: discoveryService)
        self.excludedBundleIdentifiers = Set(excludedBundleIdentifiers.map { $0.lowercased() })
        self.excludedBundleURLs = excludedBundleURLs
        self.relatedFileScanning = relatedFileScanning ?? .live(scanner: scanner)
        self.planner = planner
        self.executor = executor
        self.verifier = verifier
        self.runningApplicationMonitor = runningApplicationMonitor
        self.receiptStore = receiptStore
    }

    public var visibleApps: [InstalledApp] {
        let query = appSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = apps.filter { app in
            matchesSearch(app, query: query) && matchesFilter(app)
        }
        return sortedApps(filtered)
    }

    public var reviewCandidates: [RelatedFileCandidate] {
        switch cleanupMode {
        case .uninstall:
            candidates
        case .resetData:
            candidates.filter { $0.kind != .appBundle }
        }
    }

    public var selectedReviewCandidates: [RelatedFileCandidate] {
        reviewCandidates.filter { selectedCandidateIDs.contains($0.id) && !$0.isProtected }
    }

    public func loadApps() async {
        await reloadApps(selectFirstWhenEmpty: true)
    }

    public func refreshApps() async {
        await reloadApps(selectFirstWhenEmpty: false)
    }

    private func reloadApps(selectFirstWhenEmpty: Bool) async {
        isLoadingApps = true
        defer { isLoadingApps = false }
        applicationDiscoveryIssues = []
        let previousSelection = selectedApp
        let result = await applicationDiscovering.discover()
        let refreshedApps = result.value.filter { !isExcludedCurrentApplication($0) }
        apps = refreshedApps
        applicationDiscoveryIssues = result.issues
        hasLoadedApps = true

        if let previousSelection {
            if let refreshedSelection = refreshedApps.first(where: { isSameApp($0, previousSelection) }),
               isVisibleApp(refreshedSelection) {
                selectedApp = refreshedSelection
            } else {
                selectedApp = nil
                clearReviewState()
            }
        } else if selectFirstWhenEmpty {
            selectApp(visibleApps.first)
        } else {
            clearReviewState()
        }
        errorMessage = nil
    }

    public func selectApp(id: InstalledApp.ID?) {
        selectApp(apps.first { $0.id == id })
    }

    public func selectApp(_ app: InstalledApp?) {
        guard selectedApp?.id != app?.id else { return }
        selectedApp = app
        clearReviewState()
    }

    public func scanSelectedApp() async {
        guard let selectedApp else { return }
        isScanning = true
        defer { isScanning = false }
        clearReviewState()
        let result = await relatedFileScanning.scan(selectedApp)
        candidates = result.value
        relatedFileScanIssues = result.issues
        selectedCandidateIDs = Set(candidates.filter(\.defaultSelected).map(\.id))
        errorMessage = nil
    }

    public func makePlan() throws -> DeletionPlan {
        guard let selectedApp else { throw DeletionPlannerError.emptySelection }
        return try planner.makePlan(app: selectedApp, candidates: candidates, selectedIDs: selectedCandidateIDs)
    }

    public func makeResetPlan() throws -> DeletionPlan {
        guard let selectedApp else { throw DeletionPlannerError.emptySelection }
        let resetCandidates = candidates.filter { $0.kind != .appBundle }
        return try planner.makePlan(app: selectedApp, candidates: resetCandidates, selectedIDs: selectedCandidateIDs)
    }

    @discardableResult
    public func deleteConfirmedItems(
        confirmation: String,
        force: Bool = false,
        mode: DeletionMode = .moveToTrash
    ) async -> DeletionReportViewModel? {
        guard !isDeleting else { return nil }
        if let selectedApp, runningApplicationMonitor.isRunning(selectedApp) {
            clearDeletionOutcome()
            errorMessage = "Quit \(selectedApp.displayName) before deleting it."
            return nil
        }

        isDeleting = true
        defer { isDeleting = false }

        do {
            let plan = try makePlan()
            let results = await executor.execute(plan: plan, confirmation: confirmation, force: force, mode: mode)
            let verificationResults = await verifier.verify(plan: plan, executionResults: results)
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
                confirmationMatched: results.allSatisfy { $0.errorMessage != DeletionExecutionErrorMessage.confirmationMismatch }
            )
            let report = DeletionReportViewModel(receipt: receipt)
            do {
                try receiptStore.append(receipt)
                errorMessage = nil
            } catch {
                errorMessage = "Could not save deletion history: \(error.localizedDescription)"
            }
            deletionResults = results
            let removedSelectedApp = reconcileDeletion(
                plan: plan,
                verificationResults: verificationResults
            )
            if removedSelectedApp {
                if shouldShowDeletionReport(receipt) {
                    deletionReport = report
                }
            } else {
                deletionReport = report
            }
            return report
        } catch {
            clearDeletionOutcome()
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    public func resetSelectedData(confirmation: String) async -> DeletionReportViewModel? {
        guard !isDeleting else { return nil }
        if let selectedApp, runningApplicationMonitor.isRunning(selectedApp) {
            clearDeletionOutcome()
            errorMessage = "Quit \(selectedApp.displayName) before resetting its data."
            return nil
        }

        isDeleting = true
        defer { isDeleting = false }

        do {
            let plan = try makeResetPlan()
            let results = await executor.execute(
                plan: plan,
                confirmation: confirmation,
                mode: .moveToTrash,
                requiredConfirmation: ApplicationCleanupMode.resetData.confirmationPhrase
            )
            let verificationResults = await verifier.verify(plan: plan, executionResults: results)
            let receipt = DeletionReceipt(
                appName: plan.app.displayName,
                bundleIdentifier: plan.app.bundleIdentifier,
                bundlePath: plan.app.bundleURL.path,
                action: .appReset,
                selectedCandidates: plan.candidates.map {
                    DeletionReceiptCandidate(path: $0.url.path, kind: $0.kind, size: $0.size, safety: $0.safety, evidence: $0.evidence)
                },
                executionResults: results,
                verificationResults: verificationResults,
                confirmationMatched: results.allSatisfy { $0.errorMessage != DeletionExecutionErrorMessage.confirmationMismatch }
            )
            let report = DeletionReportViewModel(receipt: receipt)
            do {
                try receiptStore.append(receipt)
                errorMessage = nil
            } catch {
                errorMessage = "Could not save deletion history: \(error.localizedDescription)"
            }
            deletionResults = results
            deletionReport = report

            if verificationResults.contains(where: { $0.status == .deleted }) {
                await refreshReviewAfterReset(app: plan.app)
            }
            return report
        } catch {
            clearDeletionOutcome()
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    private func reconcileDeletion(
        plan: DeletionPlan,
        verificationResults: [DeletionVerificationResult]
    ) -> Bool {
        if deletedSelectedAppBundle(plan: plan, verificationResults: verificationResults) {
            removeDeletedAppFromList(plan.app)
            return true
        }

        let deletedPaths = Set(
            verificationResults
                .filter { $0.status == .deleted }
                .map { normalizedPath($0.path) }
        )
        let deletedCandidateIDs = Set(
            plan.candidates
                .filter { deletedPaths.contains(normalizedPath($0.url.path)) }
                .map(\.id)
        )
        candidates.removeAll { deletedCandidateIDs.contains($0.id) }
        selectedCandidateIDs.subtract(deletedCandidateIDs)
        return false
    }

    private func deletedSelectedAppBundle(
        plan: DeletionPlan,
        verificationResults: [DeletionVerificationResult]
    ) -> Bool {
        let selectedAppBundlePaths = Set(
            plan.candidates
                .filter { $0.kind == .appBundle && isSameURL($0.url, plan.app.bundleURL) }
                .map { normalizedPath($0.url.path) }
        )
        guard !selectedAppBundlePaths.isEmpty else { return false }

        return verificationResults.contains { result in
            result.status == .deleted && selectedAppBundlePaths.contains(normalizedPath(result.path))
        }
    }

    private func shouldShowDeletionReport(_ receipt: DeletionReceipt) -> Bool {
        receipt.executionResults.contains { !$0.success }
            || receipt.verificationResults.contains { $0.status == .stillExists || $0.status == .permissionDenied }
    }

    private func removeDeletedAppFromList(_ deletedApp: InstalledApp) {
        apps.removeAll { $0.id == deletedApp.id }
        selectedApp = nil
        clearReviewState()
    }

    private func clearReviewState() {
        candidates = []
        selectedCandidateIDs = []
        relatedFileScanIssues = []
        cleanupMode = .uninstall
        clearDeletionOutcome()
    }

    private func reconcileCleanupModeSelection() {
        let allowedIDs = Set(reviewCandidates.map(\.id))
        selectedCandidateIDs.formIntersection(allowedIDs)
        if cleanupMode == .uninstall {
            selectedCandidateIDs.formUnion(
                candidates
                    .filter { $0.kind == .appBundle && $0.defaultSelected && !$0.isProtected }
                    .map(\.id)
            )
        }
        clearDeletionOutcome()
    }

    private func refreshReviewAfterReset(app: InstalledApp) async {
        guard selectedApp.map({ isSameApp($0, app) }) == true else { return }
        let result = await relatedFileScanning.scan(app)
        candidates = result.value
        relatedFileScanIssues = result.issues
        selectedCandidateIDs = Set(
            reviewCandidates
                .filter { $0.defaultSelected && !$0.isProtected }
                .map(\.id)
        )
    }

    private func clearDeletionOutcome() {
        deletionResults = []
        deletionReport = nil
    }

    private func reconcileVisibleSelection() {
        guard let selectedApp else { return }
        guard isVisibleApp(selectedApp) else {
            self.selectedApp = nil
            clearReviewState()
            return
        }
    }

    private func isVisibleApp(_ app: InstalledApp) -> Bool {
        visibleApps.contains(where: { isSameApp($0, app) })
    }

    private func isExcludedCurrentApplication(_ app: InstalledApp) -> Bool {
        if let bundleIdentifier = app.bundleIdentifier?.lowercased(),
           excludedBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }
        return excludedBundleURLs.contains { isSameURL(app.bundleURL, $0) }
    }

    private func matchesSearch(_ app: InstalledApp, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return app.displayName.lowercased().contains(query)
            || (app.bundleIdentifier?.lowercased().contains(query) ?? false)
            || app.bundleURL.path.lowercased().contains(query)
    }

    private func matchesFilter(_ app: InstalledApp) -> Bool {
        switch appFilter {
        case .all:
            return true
        case .userApplications:
            return isUserApplication(app)
        case .largeApplications:
            return app.bundleSize >= 500 * 1024 * 1024
        }
    }

    private func sortedApps(_ apps: [InstalledApp]) -> [InstalledApp] {
        switch appSort {
        case .nameAscending:
            return apps.sorted { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
        case .sizeDescending:
            return apps.sorted { lhs, rhs in
                if lhs.bundleSize == rhs.bundleSize {
                    return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                }
                return lhs.bundleSize > rhs.bundleSize
            }
        case .pathAscending:
            return apps.sorted { lhs, rhs in
                lhs.bundleURL.path.localizedStandardCompare(rhs.bundleURL.path) == .orderedAscending
            }
        }
    }

    private func isUserApplication(_ app: InstalledApp) -> Bool {
        let path = normalizedAppURL(app.bundleURL).path
        return path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path + "/")
            || path.hasPrefix("/Users/")
    }

    private func isSameApp(_ lhs: InstalledApp, _ rhs: InstalledApp) -> Bool {
        normalizedAppURL(lhs.bundleURL) == normalizedAppURL(rhs.bundleURL)
    }

    private func normalizedAppURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private func isSameURL(_ lhs: URL, _ rhs: URL) -> Bool {
        normalizedAppURL(lhs) == normalizedAppURL(rhs)
    }

    private func normalizedPath(_ path: String) -> String {
        normalizedAppURL(URL(fileURLWithPath: path)).path
    }
}
