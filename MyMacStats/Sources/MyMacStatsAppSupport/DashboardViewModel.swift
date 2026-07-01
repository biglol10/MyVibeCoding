import Combine
import Foundation
import MyMacStatsCore

public enum HistoryRange: String, CaseIterable, Identifiable, Sendable {
    case oneMinute
    case fiveMinutes

    public var id: Self { self }

    public var title: String {
        switch self {
        case .oneMinute: "1m"
        case .fiveMinutes: "5m"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .fiveMinutes: 300
        }
    }
}

private struct ProcessSortPreference: Equatable {
    let key: ProcessSortKey
    let ascending: Bool
}

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var snapshot: SystemMetricsSnapshot
    @Published public var selectedKind: MetricKind
    @Published public var searchText: String
    @Published public var sortKey: ProcessSortKey {
        didSet { saveSelectedSortPreference() }
    }
    @Published public var sortAscending: Bool {
        didSet { saveSelectedSortPreference() }
    }
    @Published public var refreshInterval: RefreshInterval
    @Published public var historyRange: HistoryRange
    @Published public var selectedProcessID: Int32?
    @Published public private(set) var pendingTerminationProcess: ProcessMetric?
    @Published public private(set) var pendingTerminationGroup: ProcessAppGroup?
    @Published public private(set) var pendingTerminationMode: ProcessTerminationMode
    @Published public var terminationMessage: String?

    private let service: SystemMetricsService
    private var terminator: ProcessTerminator
    private var terminationMessageProcessID: Int32?
    private var forceQuitCandidateGroupID: String?
    private var refreshTask: Task<Void, Never>?
    private var displayedProcessesCacheKey: ProcessDisplayCacheKey?
    private var displayedProcessesCache: [ProcessMetric] = []
    private var displayedProcessGroupsCacheKey: ProcessDisplayCacheKey?
    private var displayedProcessGroupsCache: [ProcessAppGroup] = []
    private var selectedProcessGroupID: String?
    private var sortPreferences: [MetricKind: ProcessSortPreference]
    private var isApplyingSortPreference: Bool

    public init(
        snapshot: SystemMetricsSnapshot = .empty(),
        service: SystemMetricsService = SystemMetricsService(),
        terminator: ProcessTerminator = ProcessTerminator()
    ) {
        self.snapshot = snapshot
        self.service = service
        self.terminator = terminator
        self.selectedKind = .cpu
        self.searchText = ""
        self.sortKey = .cpu
        self.sortAscending = false
        self.refreshInterval = .oneSecond
        self.historyRange = .oneMinute
        self.selectedProcessID = nil
        self.selectedProcessGroupID = nil
        self.pendingTerminationProcess = nil
        self.pendingTerminationGroup = nil
        self.pendingTerminationMode = .quit
        self.terminationMessage = nil
        self.terminationMessageProcessID = nil
        self.forceQuitCandidateGroupID = nil
        self.sortPreferences = MetricKind.defaultProcessSortPreferences
        self.isApplyingSortPreference = false
    }

    public var summaries: [MetricSummary] {
        snapshot.summaries
    }

    public var displayedProcesses: [ProcessMetric] {
        let sort = effectiveProcessSort
        let cacheKey = ProcessDisplayCacheKey(
            processes: snapshot.processes,
            searchText: searchText,
            sortKey: sort.key,
            ascending: sort.ascending
        )
        if displayedProcessesCacheKey != cacheKey {
            displayedProcessesCache = ProcessSorting.filtered(
                snapshot.processes,
                searchText: searchText,
                sortKey: sort.key,
                ascending: sort.ascending
            )
            displayedProcessesCacheKey = cacheKey
        }
        return displayedProcessesCache
    }

    public var displayedProcessGroups: [ProcessAppGroup] {
        let sort = effectiveProcessSort
        let cacheKey = ProcessDisplayCacheKey(
            processes: snapshot.processes,
            searchText: searchText,
            sortKey: sort.key,
            ascending: sort.ascending
        )
        if displayedProcessGroupsCacheKey != cacheKey {
            displayedProcessGroupsCache = ProcessGrouping.groups(
                snapshot.processes,
                searchText: searchText,
                sortKey: sort.key,
                ascending: sort.ascending
            )
            displayedProcessGroupsCacheKey = cacheKey
        }
        return displayedProcessGroupsCache
    }

    public var showsProcessControls: Bool {
        selectedKind.usesProcessList
    }

    public var selectedProcessGroup: ProcessAppGroup? {
        if let selectedProcessGroupID,
           let selected = displayedProcessGroups.first(where: { $0.id == selectedProcessGroupID }) {
            return selected
        }
        if let selectedProcessID,
           let selected = displayedProcessGroups.first(where: { group in
               group.processes.contains { $0.pid == selectedProcessID }
           }) {
            return selected
        }
        return displayedProcessGroups.first
    }

    private var effectiveProcessSort: (key: ProcessSortKey, ascending: Bool) {
        (sortKey, sortAscending)
    }

    public var selectedSummary: MetricSummary? {
        snapshot.summary(for: selectedKind)
    }

    public var selectedCauseSummary: CauseSummary? {
        CauseSummaryBuilder.summary(for: selectedKind, snapshot: snapshot)
    }

    public var displayedCPUHistory: [Double] {
        guard !snapshot.cpuHistorySamples.isEmpty else {
            return snapshot.cpuHistory
        }
        let cutoff = snapshot.updatedAt.addingTimeInterval(-historyRange.seconds)
        return snapshot.cpuHistorySamples
            .filter { $0.date >= cutoff }
            .map(\.value)
    }

    public var selectedProcess: ProcessMetric? {
        if let selectedProcessID,
           let selected = displayedProcesses.first(where: { $0.pid == selectedProcessID }) {
            return selected
        }
        return selectedProcessGroup?.processes.first ?? displayedProcesses.first
    }

    public var selectedProcessTerminationAvailability: ProcessTerminationAvailability {
        guard let selectedProcess else {
            return .denied("No process selected")
        }
        return terminator.canTerminate(terminationTargets(for: selectedProcess))
    }

    public var selectedProcessTerminationMessage: String? {
        guard selectedProcess?.pid == terminationMessageProcessID else { return nil }
        return terminationMessage
    }

    public var selectedProcessCanForceQuit: Bool {
        guard let selectedProcessGroup,
              selectedProcessGroup.id == forceQuitCandidateGroupID,
              terminator.canTerminate(selectedProcessGroup.processes).isAllowed
        else {
            return false
        }
        return true
    }

    public var pendingTerminationDisplayName: String? {
        guard let pendingTerminationProcess else { return nil }
        return pendingTerminationTargetDescription(process: pendingTerminationProcess)
    }

    public var pendingTerminationDetailText: String? {
        guard let pendingTerminationProcess else { return nil }
        if let group = pendingTerminationGroup, group.processes.count > 1 {
            return "CPU \(MetricFormatters.percent(group.cpuPercent, fractionDigits: group.cpuPercent < 10 ? 1 : 0)), Memory \(MetricFormatters.bytes(group.memoryBytes))"
        }
        return "PID \(pendingTerminationProcess.pid), CPU \(MetricFormatters.percent(pendingTerminationProcess.cpuPercent, fractionDigits: pendingTerminationProcess.cpuPercent < 10 ? 1 : 0)), Memory \(MetricFormatters.bytes(pendingTerminationProcess.memoryBytes))"
    }

    public var pendingTerminationTargetsApp: Bool {
        guard let pendingTerminationGroup else { return false }
        return pendingTerminationGroup.isApplicationTarget
    }

    public func terminationAvailability(for process: ProcessMetric) -> ProcessTerminationAvailability {
        terminator.canTerminate(terminationTargets(for: process))
    }

    public func select(_ kind: MetricKind) {
        selectedKind = kind
        selectedProcessID = nil
        selectedProcessGroupID = nil
        applySortPreference(for: kind)
    }

    public func replaceSnapshot(_ snapshot: SystemMetricsSnapshot) {
        self.snapshot = snapshot
    }

    public func selectProcess(pid: Int32) {
        selectedProcessID = pid
        selectedProcessGroupID = displayedProcessGroups.first { group in
            group.processes.contains { $0.pid == pid }
        }?.id
    }

    private func applySortPreference(for kind: MetricKind) {
        guard let preference = sortPreferences[kind] else { return }
        isApplyingSortPreference = true
        sortKey = preference.key
        sortAscending = preference.ascending
        isApplyingSortPreference = false
    }

    private func saveSelectedSortPreference() {
        guard !isApplyingSortPreference, selectedKind.usesProcessList else { return }
        sortPreferences[selectedKind] = ProcessSortPreference(key: sortKey, ascending: sortAscending)
    }

    public func requestTermination(for process: ProcessMetric) {
        let targets = terminationTargets(for: process)
        let availability = terminator.canTerminate(targets)
        guard availability.isAllowed else {
            terminationMessage = availability.reason
            terminationMessageProcessID = process.pid
            pendingTerminationProcess = nil
            pendingTerminationGroup = nil
            return
        }
        pendingTerminationProcess = process
        pendingTerminationGroup = terminationGroup(for: process)
        pendingTerminationMode = .quit
        terminationMessage = nil
        terminationMessageProcessID = nil
    }

    public func requestForceTermination(for process: ProcessMetric) {
        let targets = terminationTargets(for: process)
        let availability = terminator.canTerminate(targets)
        guard availability.isAllowed else {
            terminationMessage = availability.reason
            terminationMessageProcessID = process.pid
            pendingTerminationProcess = nil
            pendingTerminationGroup = nil
            pendingTerminationMode = .quit
            return
        }
        pendingTerminationProcess = process
        pendingTerminationGroup = terminationGroup(for: process)
        pendingTerminationMode = .forceQuit
        terminationMessage = nil
        terminationMessageProcessID = nil
    }

    public func cancelPendingTermination() {
        pendingTerminationProcess = nil
        pendingTerminationGroup = nil
        pendingTerminationMode = .quit
    }

    public func confirmPendingTermination() {
        guard let process = pendingTerminationProcess else { return }
        let mode = pendingTerminationMode
        let targets = pendingTerminationGroup?.processes ?? [process]
        let targetDescription = pendingTerminationTargetDescription(process: process)
        let targetGroupID = pendingTerminationGroup?.id ?? terminationGroup(for: process)?.id
        do {
            try terminator.terminate(targets, mode: mode)
            switch mode {
            case .quit:
                terminationMessage = "Termination requested for \(targetDescription)."
                forceQuitCandidateGroupID = targetGroupID
            case .forceQuit:
                terminationMessage = "Force quit requested for \(targetDescription)."
                forceQuitCandidateGroupID = nil
            }
            terminationMessageProcessID = process.pid
            pendingTerminationProcess = nil
            pendingTerminationGroup = nil
            pendingTerminationMode = .quit
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.refreshNow()
            }
        } catch let error as ProcessTerminationError {
            terminationMessage = error.message
            terminationMessageProcessID = process.pid
            pendingTerminationProcess = nil
            pendingTerminationGroup = nil
            pendingTerminationMode = .quit
        } catch {
            terminationMessage = "Termination failed."
            terminationMessageProcessID = process.pid
            pendingTerminationProcess = nil
            pendingTerminationGroup = nil
            pendingTerminationMode = .quit
        }
    }

    private func terminationGroup(for process: ProcessMetric) -> ProcessAppGroup? {
        displayedProcessGroups.first { group in
            group.processes.contains { $0.pid == process.pid }
        }
    }

    private func terminationTargets(for process: ProcessMetric) -> [ProcessMetric] {
        terminationGroup(for: process)?.processes ?? [process]
    }

    private func pendingTerminationTargetDescription(process: ProcessMetric) -> String {
        guard let group = pendingTerminationGroup else {
            return process.name
        }
        if group.processes.count > 1 {
            return "\(group.name) (\(group.processes.count) processes)"
        }
        return group.isApplicationTarget ? group.name : process.name
    }

    public func refreshNow() async {
        snapshot = await service.refresh()
    }

    public func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshNow()
                let interval = self.refreshInterval.seconds
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}

private extension ProcessAppGroup {
    var isApplicationTarget: Bool {
        id.hasPrefix("app:") || processes.count > 1
    }
}

private struct ProcessDisplayCacheKey: Equatable {
    let processes: [ProcessMetric]
    let searchText: String
    let sortKey: ProcessSortKey
    let ascending: Bool
}

private extension MetricKind {
    var usesProcessList: Bool {
        switch self {
        case .cpu, .memory, .processes:
            true
        case .disk, .network, .battery:
            false
        }
    }

    static var defaultProcessSortPreferences: [MetricKind: ProcessSortPreference] {
        [
            .cpu: ProcessSortPreference(key: .cpu, ascending: false),
            .memory: ProcessSortPreference(key: .memory, ascending: false),
            .processes: ProcessSortPreference(key: .cpu, ascending: false)
        ]
    }
}
