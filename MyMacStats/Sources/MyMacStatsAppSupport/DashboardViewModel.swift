import Combine
import Foundation
import MyMacStatsCore

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var snapshot: SystemMetricsSnapshot
    @Published public var selectedKind: MetricKind
    @Published public var searchText: String
    @Published public var sortKey: ProcessSortKey
    @Published public var sortAscending: Bool
    @Published public var refreshInterval: RefreshInterval
    @Published public var selectedProcessID: Int32?

    private let service: SystemMetricsService
    private var refreshTask: Task<Void, Never>?

    public init(snapshot: SystemMetricsSnapshot = .empty(), service: SystemMetricsService = SystemMetricsService()) {
        self.snapshot = snapshot
        self.service = service
        self.selectedKind = .cpu
        self.searchText = ""
        self.sortKey = .cpu
        self.sortAscending = false
        self.refreshInterval = .oneSecond
        self.selectedProcessID = nil
    }

    public var summaries: [MetricSummary] {
        snapshot.summaries
    }

    public var displayedProcesses: [ProcessMetric] {
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

        return ProcessSorting.filtered(
            snapshot.processes,
            searchText: searchText,
            sortKey: effectiveSort,
            ascending: effectiveAscending
        )
    }

    public var selectedSummary: MetricSummary? {
        snapshot.summary(for: selectedKind)
    }

    public var selectedProcess: ProcessMetric? {
        if let selectedProcessID,
           let selected = displayedProcesses.first(where: { $0.pid == selectedProcessID }) {
            return selected
        }
        return displayedProcesses.first
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
