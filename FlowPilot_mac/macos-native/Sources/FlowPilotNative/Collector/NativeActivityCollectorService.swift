import AppKit
import Combine
import FlowPilotNativeCore
import Foundation

@MainActor
final class NativeActivityCollectorService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var pauseReason: String?
    @Published private(set) var controlState = CollectionControlState()

    var isManuallyPaused: Bool { controlState.isManuallyPaused }

    var statusText: String {
        if lastError != nil { return "수집 오류" }
        if controlState.isManuallyPaused { return "사용자 일시정지" }
        if let pauseReason { return pauseReason }
        return isRunning ? "Swift 수집 중" : "수집 중지"
    }

    private let reader: ActivitySampleReader
    private let database: FlowPilotDatabase
    private let accumulator: ActivitySessionAccumulator
    private let onSaved: () -> Void
    private var timer: Timer?
    private var windowObservationSaveGate = WindowObservationSaveGate(minimumInterval: 60)

    init(
        databaseURL: URL,
        sampleInterval: TimeInterval = 5,
        reader: ActivitySampleReader = MacActivityReader(),
        accumulator: ActivitySessionAccumulator = ActivitySessionAccumulator(),
        onSaved: @escaping () -> Void
    ) {
        self.reader = reader
        self.database = FlowPilotDatabase(path: databaseURL.path)
        self.accumulator = accumulator
        self.onSaved = onSaved
        self.sampleInterval = sampleInterval
    }

    private let sampleInterval: TimeInterval

    @discardableResult
    private func scheduleTimerIfNeeded() -> Bool {
        guard timer == nil, !controlState.isManuallyPaused else { return false }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.collectOnce()
            }
        }
        return true
    }

    func start() {
        guard scheduleTimerIfNeeded() else { return }
        collectOnce()
    }

    func pauseCollection() {
        guard controlState.pause() else { return }
        timer?.invalidate()
        timer = nil
        isRunning = false
        accumulator.reset()
    }

    func resumeCollection() {
        guard controlState.resume() else { return }
        lastError = nil
        guard scheduleTimerIfNeeded() else { return }
        collectOnce()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func collectOnce() {
        guard !controlState.isManuallyPaused else { return }

        let legacyFlowPilotIsRunning = self.legacyFlowPilotIsRunning
        let snapshot = legacyFlowPilotIsRunning ? nil : reader.readSnapshot()
        let observationDecision = CollectionObservationDecision.decide(
            legacyFlowPilotIsRunning: legacyFlowPilotIsRunning,
            snapshotIsAvailable: snapshot != nil
        )

        if legacyFlowPilotIsRunning {
            pauseReason = "기존 FlowPilot이 실행 중이라 Swift 수집을 일시중지했습니다."
        } else {
            pauseReason = nil
        }

        guard observationDecision == .observe, let snapshot else {
            accumulator.reset()
            return
        }

        let records = accumulator.observe(snapshot.primarySample).map { record in
            do {
                return BrowserSessionEnricher.enrich(
                    session: record,
                    events: try database.listRecentBrowserEvents(limit: 100)
                )
            } catch {
                return record
            }
        }
        do {
            try database.saveSessions(records)
            if let primarySessionID = records.last?.id,
               windowObservationSaveGate.consumeIfDue(at: snapshot.primarySample.observedAt) {
                try database.saveWindowObservations(
                    sessionID: primarySessionID,
                    observations: snapshot.visibleWindows
                )
            }
            lastError = nil
            onSaved()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private var legacyFlowPilotIsRunning: Bool {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: "app.flowpilot.desktop")
            .contains { !$0.isTerminated }
    }
}
