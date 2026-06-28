import AppKit
import Combine
import FlowPilotNativeCore
import Foundation

@MainActor
final class NativeActivityCollectorService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var pauseReason: String?

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

    func start() {
        guard timer == nil else {
            return
        }

        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.collectOnce()
            }
        }
        collectOnce()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func collectOnce() {
        if legacyFlowPilotIsRunning {
            pauseReason = "기존 FlowPilot이 실행 중이라 Swift 수집을 일시중지했습니다."
            return
        }
        pauseReason = nil

        guard let snapshot = reader.readSnapshot() else {
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
