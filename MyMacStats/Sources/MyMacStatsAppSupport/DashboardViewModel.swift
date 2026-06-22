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

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var snapshot: SystemMetricsSnapshot
    @Published public var selectedKind: MetricKind
    @Published public var searchText: String
    @Published public var sortKey: ProcessSortKey
    @Published public var sortAscending: Bool
    @Published public var refreshInterval: RefreshInterval
    @Published public var historyRange: HistoryRange
    @Published public var selectedProcessID: Int32?
    @Published public private(set) var pendingTerminationProcess: ProcessMetric?
    @Published public private(set) var pendingTerminationMode: ProcessTerminationMode
    @Published public var terminationMessage: String?

    private let service: SystemMetricsService
    private var terminator: ProcessTerminator
    private var terminationMessageProcessID: Int32?
    private var forceQuitCandidateProcessID: Int32?
    private var refreshTask: Task<Void, Never>?
    private var displayedProcessesCacheKey: ProcessDisplayCacheKey?
    private var displayedProcessesCache: [ProcessMetric] = []
    private var displayedProcessGroupsCacheKey: ProcessDisplayCacheKey?
    private var displayedProcessGroupsCache: [ProcessAppGroup] = []

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
        self.pendingTerminationProcess = nil
        self.pendingTerminationMode = .quit
        self.terminationMessage = nil
        self.terminationMessageProcessID = nil
        self.forceQuitCandidateProcessID = nil
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

    public var selectedProcessGroup: ProcessAppGroup? {
        if let selectedProcessID,
           let selected = displayedProcessGroups.first(where: { group in
               group.processes.contains { $0.pid == selectedProcessID }
           }) {
            return selected
        }
        return displayedProcessGroups.first
    }

    private var effectiveProcessSort: (key: ProcessSortKey, ascending: Bool) {
        let effectiveSort: ProcessSortKey
        let effectiveAscending: Bool
        switch selectedKind {
        case .cpu:
            effectiveSort = .cpu
            effectiveAscending = false
        case .memory:
            effectiveSort = .memory
            effectiveAscending = false
        case .processes:
            effectiveSort = sortKey
            effectiveAscending = sortAscending
        case .disk, .network, .battery:
            effectiveSort = sortKey
            effectiveAscending = sortAscending
        }
        return (effectiveSort, effectiveAscending)
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
        return terminator.canTerminate(selectedProcess)
    }

    public var selectedProcessTerminationMessage: String? {
        guard selectedProcess?.pid == terminationMessageProcessID else { return nil }
        return terminationMessage
    }

    public var selectedProcessCanForceQuit: Bool {
        guard let selectedProcess,
              selectedProcess.pid == forceQuitCandidateProcessID,
              terminator.canTerminate(selectedProcess).isAllowed
        else {
            return false
        }
        return true
    }

    public func terminationAvailability(for process: ProcessMetric) -> ProcessTerminationAvailability {
        terminator.canTerminate(process)
    }

    public func select(_ kind: MetricKind) {
        selectedKind = kind
        selectedProcessID = nil
    }

    public func replaceSnapshot(_ snapshot: SystemMetricsSnapshot) {
        self.snapshot = snapshot
    }

    public func selectProcess(pid: Int32) {
        selectedProcessID = pid
    }

    public func requestTermination(for process: ProcessMetric) {
        let availability = terminator.canTerminate(process)
        guard availability.isAllowed else {
            terminationMessage = availability.reason
            terminationMessageProcessID = process.pid
            pendingTerminationProcess = nil
            return
        }
        pendingTerminationProcess = process
        pendingTerminationMode = .quit
        terminationMessage = nil
        terminationMessageProcessID = nil
    }

    public func requestForceTermination(for process: ProcessMetric) {
        let availability = terminator.canTerminate(process)
        guard availability.isAllowed else {
            terminationMessage = availability.reason
            terminationMessageProcessID = process.pid
            pendingTerminationProcess = nil
            pendingTerminationMode = .quit
            return
        }
        pendingTerminationProcess = process
        pendingTerminationMode = .forceQuit
        terminationMessage = nil
        terminationMessageProcessID = nil
    }

    public func cancelPendingTermination() {
        pendingTerminationProcess = nil
        pendingTerminationMode = .quit
    }

    public func confirmPendingTermination() {
        guard let process = pendingTerminationProcess else { return }
        let mode = pendingTerminationMode
        do {
            try terminator.terminate(process, mode: mode)
            switch mode {
            case .quit:
                terminationMessage = "Termination requested for \(process.name)."
                forceQuitCandidateProcessID = process.pid
            case .forceQuit:
                terminationMessage = "Force quit requested for \(process.name)."
                forceQuitCandidateProcessID = nil
            }
            terminationMessageProcessID = process.pid
            pendingTerminationProcess = nil
            pendingTerminationMode = .quit
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.refreshNow()
            }
        } catch let error as ProcessTerminationError {
            terminationMessage = error.message
            terminationMessageProcessID = process.pid
            pendingTerminationProcess = nil
            pendingTerminationMode = .quit
        } catch {
            terminationMessage = "Termination failed."
            terminationMessageProcessID = process.pid
            pendingTerminationProcess = nil
            pendingTerminationMode = .quit
        }
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

private struct ProcessDisplayCacheKey: Equatable {
    let processes: [ProcessMetric]
    let searchText: String
    let sortKey: ProcessSortKey
    let ascending: Bool
}
