# Metric Refresh Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce MyMacStats' sampling overhead and preserve useful last-known-good values across one transient sampler failure without weakening process-termination identity checks.

**Architecture:** Keep the existing single dashboard refresh loop. `SystemMetricsService` owns per-metric cadence and cache state, assembles every snapshot from fresh or retained values, and exposes whether process data came from a forced fresh sample. `DashboardViewModel` passes the selected base interval for scheduled refreshes and requests a forced process refresh before termination.

**Tech Stack:** Swift 6, SwiftUI, Foundation concurrency, macOS 14, XCTest

## Global Constraints

- Keep macOS 14 and Swift 6 as the minimum platform/toolchain.
- Add no third-party dependency.
- Keep one refresh task in `DashboardViewModel`; do not create a timer per metric.
- CPU, memory, and network use the selected base interval.
- Processes use `max(base interval, 2 seconds)`.
- Disk and battery use `max(base interval, 10 seconds)`.
- Disk-space candidates keep the existing 60-second background interval.
- A skipped sample is not a failed sample.
- Health evaluation and debounce advance only for a new successful sample.
- First failure after success retains the last value as stale; second consecutive due failure becomes unavailable.
- Cached CPU values do not extend CPU history.
- Cached memory values do not advance swap-increase tracking.
- Process termination validation must use a newly sampled process list and fail closed when that sample fails.
- Preserve current PID/name/path/bundle identity validation and protected-process rules.

---

## File Structure

- `Sources/MyMacStatsAppSupport/SystemMetricsService.swift`: refresh reasons, cadence calculation, per-metric caches, stale/unavailable presentation, process freshness.
- `Sources/MyMacStatsAppSupport/DashboardViewModel.swift`: scheduled refresh wiring and forced termination-validation refresh.
- `Tests/MyMacStatsAppSupportTests/SystemMetricsServiceTests.swift`: deterministic cadence, cache, failure, recovery, and process freshness tests.
- `Tests/MyMacStatsAppSupportTests/DashboardViewModelTests.swift`: destructive-action fail-closed and forced-resampling tests.
- `README.md`: user-facing cadence and stale-data behavior.
- `docs/feature-verification-checklist-2026-08-04.md`: verified implementation status and updated test count.

### Task 1: Add Per-Metric Cadence And Process Sampling Failure Semantics

**Files:**
- Modify: `Sources/MyMacStatsAppSupport/SystemMetricsService.swift:4-13`
- Modify: `Sources/MyMacStatsAppSupport/SystemMetricsService.swift:74-169`
- Modify: `Sources/MyMacStatsAppSupport/SystemMetricsService.swift:314-355`
- Test: `Tests/MyMacStatsAppSupportTests/SystemMetricsServiceTests.swift`
- Test support updates: `Tests/MyMacStatsAppSupportTests/DashboardViewModelTests.swift`

**Interfaces:**
- Consumes: `RefreshInterval.seconds`, existing `SystemSampler` metric methods, `SystemMetricsSnapshot`.
- Produces: `SystemMetricsRefreshReason`, `SystemMetricsService.refresh(now:reason:)`, optional `SystemSampler.sampleProcesses()`, `SystemMetricsSnapshot.processesAreFresh`.

- [x] **Step 1: Write the failing cadence test**

Add a main-actor recording sampler whose values can be changed and whose call counts are observable. The process return value is optional so a command failure differs from a successful empty list.

```swift
@MainActor
private final class RecordingSystemSampler: SystemSampler {
    var cpuResult: CPUSnapshot?
    var memoryResult: MemorySnapshot?
    var diskResult: DiskSnapshot?
    var networkResult: NetworkSnapshot?
    var batteryResult: BatterySnapshot?
    var processResult: [ProcessMetric]?

    private(set) var cpuCallCount = 0
    private(set) var memoryCallCount = 0
    private(set) var diskCallCount = 0
    private(set) var networkCallCount = 0
    private(set) var batteryCallCount = 0
    private(set) var processCallCount = 0

    init(
        cpu: CPUSnapshot?,
        memory: MemorySnapshot?,
        disk: DiskSnapshot?,
        network: NetworkSnapshot?,
        battery: BatterySnapshot?,
        processes: [ProcessMetric]?
    ) {
        cpuResult = cpu
        memoryResult = memory
        diskResult = disk
        networkResult = network
        batteryResult = battery
        processResult = processes
    }

    func sampleCPU() async -> CPUSnapshot? {
        cpuCallCount += 1
        return cpuResult
    }

    func sampleMemory() async -> MemorySnapshot? {
        memoryCallCount += 1
        return memoryResult
    }

    func sampleDisk() async -> DiskSnapshot? {
        diskCallCount += 1
        return diskResult
    }

    func sampleNetwork() async -> NetworkSnapshot? {
        networkCallCount += 1
        return networkResult
    }

    func sampleBattery() async -> BatterySnapshot? {
        batteryCallCount += 1
        return batteryResult
    }

    func sampleDiskSpaceCandidates() async -> [DiskSpaceCandidate] { [] }

    func sampleProcesses() async -> [ProcessMetric]? {
        processCallCount += 1
        return processResult
    }
}
```

Add this behavior test using literal call-count expectations:

```swift
func testScheduledRefreshUsesMetricSpecificCadence() async {
    let now = Date(timeIntervalSince1970: 1_000)
    let sampler = RecordingSystemSampler(
        cpu: cpuSnapshot(at: now),
        memory: memorySnapshot(at: now),
        disk: diskSnapshot(at: now),
        network: networkSnapshot(at: now),
        battery: batterySnapshot(at: now),
        processes: [process]
    )
    let service = SystemMetricsService(
        sampler: sampler,
        evaluator: HealthEvaluator(debounceSamples: 1)
    )

    _ = await service.refresh(now: now, reason: .scheduled(baseInterval: 1))
    _ = await service.refresh(now: now.addingTimeInterval(1), reason: .scheduled(baseInterval: 1))

    XCTAssertEqual(sampler.cpuCallCount, 2)
    XCTAssertEqual(sampler.memoryCallCount, 2)
    XCTAssertEqual(sampler.networkCallCount, 2)
    XCTAssertEqual(sampler.processCallCount, 1)
    XCTAssertEqual(sampler.diskCallCount, 1)
    XCTAssertEqual(sampler.batteryCallCount, 1)

    _ = await service.refresh(now: now.addingTimeInterval(2), reason: .scheduled(baseInterval: 1))
    XCTAssertEqual(sampler.processCallCount, 2)

    _ = await service.refresh(now: now.addingTimeInterval(10), reason: .scheduled(baseInterval: 1))
    XCTAssertEqual(sampler.diskCallCount, 2)
    XCTAssertEqual(sampler.batteryCallCount, 2)
}
```

- [x] **Step 2: Run the cadence test and verify RED**

Run:

```bash
swift test --filter SystemMetricsServiceTests/testScheduledRefreshUsesMetricSpecificCadence
```

Expected: compilation fails because `SystemMetricsRefreshReason`, the `reason:` argument, and optional `sampleProcesses()` do not exist.

- [x] **Step 3: Implement refresh reasons, cadence state, and optional process results**

Add these public contracts near `SystemSampler`:

```swift
public enum SystemMetricsRefreshReason: Equatable, Sendable {
    case scheduled(baseInterval: TimeInterval)
    case terminationValidation(baseInterval: TimeInterval)

    var baseInterval: TimeInterval {
        switch self {
        case .scheduled(let interval), .terminationValidation(let interval): interval
        }
    }

    var forcesProcessSampling: Bool {
        if case .terminationValidation = self { return true }
        return false
    }
}
```

Change the protocol signature and default sampler implementation:

```swift
func sampleProcesses() async -> [ProcessMetric]?

public func sampleProcesses() async -> [ProcessMetric]? {
    let processSampler = processSampler
    return await Task.detached(priority: .utility) {
        try? processSampler.sample()
    }.value
}
```

Add `processesAreFresh` to `SystemMetricsSnapshot`, defaulting to `true` in the public initializer for source compatibility and to `false` in `.empty()`.

Change the service entry point without breaking existing direct callers:

```swift
public func refresh(
    now: Date = Date(),
    reason: SystemMetricsRefreshReason = .scheduled(baseInterval: 1)
) async -> SystemMetricsSnapshot
```

Add a private cache type that separates due checks from async sampling:

```swift
private struct MetricSampleCache<Value> {
    var value: Value?
    var lastSuccessAt: Date?
    var lastAttemptAt: Date?
    var consecutiveFailures = 0

    func isDue(at now: Date, cadence: TimeInterval, forced: Bool = false) -> Bool {
        guard !forced, let lastAttemptAt else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= cadence
    }

    mutating func record(_ result: Value?, at now: Date) {
        lastAttemptAt = now
        if let result {
            value = result
            lastSuccessAt = now
            consecutiveFailures = 0
        } else {
            consecutiveFailures += 1
        }
    }
}
```

Keep the last successful `MetricSummary` for each `MetricKind`. A cadence skip reuses that summary without calling `HealthEvaluator`, so skipped Disk/Battery ticks cannot satisfy the two-sample debounce.

Store one cache for every metric. In `refresh(now:reason:)`, calculate these cadences:

```swift
let base = max(reason.baseInterval, 1)
let processCadence = max(base, 2)
let slowCadence = max(base, 10)
```

Only invoke each sampler when its cache reports due. Force only process sampling for `.terminationValidation`. Assemble the snapshot from cache values and set `processesAreFresh` only when the current refresh performed a successful process sample.

Update every test `SystemSampler` conformance to return `[ProcessMetric]?`.

- [x] **Step 4: Run focused and full service tests to verify GREEN**

Run:

```bash
swift test --filter SystemMetricsServiceTests
```

Expected: all service tests pass. Update old tests that expected every sampler to run on every timestamp so their timestamps cross the new cadence only when the test intends a fresh value.

- [x] **Step 5: Commit cadence behavior**

```bash
git add Sources/MyMacStatsAppSupport/SystemMetricsService.swift Tests/MyMacStatsAppSupportTests/SystemMetricsServiceTests.swift Tests/MyMacStatsAppSupportTests/DashboardViewModelTests.swift
git commit -m "feat: add per-metric sampling cadence"
```

### Task 2: Retain One Last-Known-Good Sample And Expose Staleness

**Files:**
- Modify: `Sources/MyMacStatsAppSupport/SystemMetricsService.swift:108-311`
- Test: `Tests/MyMacStatsAppSupportTests/SystemMetricsServiceTests.swift`

**Interfaces:**
- Consumes: `MetricSampleCache<Value>`, `SystemMetricsRefreshReason`, `SystemMetricsSnapshot.processesAreFresh` from Task 1.
- Produces: one-failure stale presentation, two-failure unavailable transition, recovery behavior, fresh-only CPU history.

- [x] **Step 1: Write failing stale/recovery tests**

Add a test that proves stale data keeps its original timestamp and does not extend CPU history:

```swift
func testFirstCPUFailureRetainsLastValueThenSecondFailureBecomesUnavailable() async {
    let start = Date(timeIntervalSince1970: 2_000)
    let sampler = recordingSampler(at: start)
    let service = SystemMetricsService(
        sampler: sampler,
        evaluator: HealthEvaluator(cpuSustainedSeconds: 0, debounceSamples: 1)
    )

    _ = await service.refresh(now: start, reason: .scheduled(baseInterval: 1))
    sampler.cpuResult = nil

    let stale = await service.refresh(
        now: start.addingTimeInterval(1),
        reason: .scheduled(baseInterval: 1)
    )

    XCTAssertEqual(stale.cpu?.totalUsagePercent, 40)
    XCTAssertEqual(stale.summary(for: .cpu)?.health, .warning)
    XCTAssertTrue(stale.summary(for: .cpu)?.detailText?.contains("Using last sample") == true)
    XCTAssertEqual(stale.summary(for: .cpu)?.updatedAt, start)
    XCTAssertEqual(stale.cpuHistory, [40])

    let unavailable = await service.refresh(
        now: start.addingTimeInterval(2),
        reason: .scheduled(baseInterval: 1)
    )

    XCTAssertNil(unavailable.cpu)
    XCTAssertEqual(unavailable.summary(for: .cpu)?.health, .unavailable)
    XCTAssertEqual(unavailable.cpuHistory, [40])

    sampler.cpuResult = cpuSnapshot(usage: 25, at: start.addingTimeInterval(3))
    let recovered = await service.refresh(
        now: start.addingTimeInterval(3),
        reason: .scheduled(baseInterval: 1)
    )

    XCTAssertEqual(recovered.cpu?.totalUsagePercent, 25)
    XCTAssertEqual(recovered.summary(for: .cpu)?.health, .normal)
    XCTAssertEqual(recovered.cpuHistory, [40, 25])
}
```

Add a process test that distinguishes failure from a valid empty result:

```swift
func testProcessFailuresRetainOnceThenBecomeUnavailableAndEmptySuccessRecovers() async {
    let start = Date(timeIntervalSince1970: 3_000)
    let sampler = recordingSampler(at: start)
    let service = SystemMetricsService(
        sampler: sampler,
        evaluator: HealthEvaluator(debounceSamples: 1)
    )

    _ = await service.refresh(now: start, reason: .scheduled(baseInterval: 1))
    sampler.processResult = nil

    let stale = await service.refresh(
        now: start.addingTimeInterval(2),
        reason: .scheduled(baseInterval: 1)
    )
    XCTAssertEqual(stale.processes.map(\.name), ["Safari"])
    XCTAssertEqual(stale.summary(for: .processes)?.health, .warning)
    XCTAssertFalse(stale.processesAreFresh)

    let unavailable = await service.refresh(
        now: start.addingTimeInterval(4),
        reason: .scheduled(baseInterval: 1)
    )
    XCTAssertEqual(unavailable.processes, [])
    XCTAssertEqual(unavailable.summary(for: .processes)?.health, .unavailable)

    sampler.processResult = []
    let recovered = await service.refresh(
        now: start.addingTimeInterval(6),
        reason: .scheduled(baseInterval: 1)
    )
    XCTAssertEqual(recovered.processes, [])
    XCTAssertEqual(recovered.summary(for: .processes)?.health, .normal)
    XCTAssertTrue(recovered.processesAreFresh)
}
```

Add a disk test showing that a nil result while disk is not due does not count as a failure. At `start + 1`, the summary remains normal; at `start + 10`, the first due failure becomes stale warning rather than unavailable.

- [x] **Step 2: Run stale tests and verify RED**

Run:

```bash
swift test --filter SystemMetricsServiceTests/testFirstCPUFailureRetainsLastValueThenSecondFailureBecomesUnavailable
swift test --filter SystemMetricsServiceTests/testProcessFailuresRetainOnceThenBecomeUnavailableAndEmptySuccessRecovers
```

Expected: tests fail because cached values are still presented without explicit stale status or are removed immediately, and process freshness/failure transitions are not complete.

- [x] **Step 3: Implement cache presentation states**

Add an internal presentation enum and computed state:

```swift
private enum SamplePresentationState: Equatable {
    case fresh
    case stale
    case unavailable
}

private extension MetricSampleCache {
    var presentationState: SamplePresentationState {
        guard value != nil else { return .unavailable }
        if consecutiveFailures == 0 { return .fresh }
        if consecutiveFailures == 1 { return .stale }
        return .unavailable
    }

    var presentedValue: Value? {
        presentationState == .unavailable ? nil : value
    }
}
```

Build and store a new summary only when a sampler returns a fresh value. A cadence skip reuses the stored successful summary unchanged and does not call `HealthEvaluator.debouncedHealth`. For stale values, derive a copy from the stored successful summary, append `Using last sample` to detail text, and return `.warning` unless the stored health is already `.critical`. For unavailable values, use the existing unavailable text and the current refresh time.

Append CPU history only inside the branch where a due CPU call returned non-nil. Call `isMemorySwapIncreasing` only inside the branch where a due memory call returned non-nil. Remove the old network-only consecutive-failure counter because the shared cache state now owns that behavior.

For Processes, present cached values only through the first failure and pass its presentation state into `buildSummaries` so the summary can be normal, warning, or unavailable.

Add `testSkippedDiskSampleDoesNotAdvanceHealthDebounce`: provide two low-free-space Disk results, refresh at `start`, `start + 1`, and `start + 10`, and assert the skipped `start + 1` refresh remains normal while the second real Disk sample at `start + 10` is the first debounce candidate and also remains normal. A third real Disk sample at `start + 20` must become critical.

- [x] **Step 4: Verify focused tests and all AppSupport tests**

Run:

```bash
swift test --filter SystemMetricsServiceTests
swift test --filter MyMacStatsAppSupportTests
```

Expected: all selected tests pass with no failures or concurrency warnings.

- [x] **Step 5: Commit stale-value behavior**

```bash
git add Sources/MyMacStatsAppSupport/SystemMetricsService.swift Tests/MyMacStatsAppSupportTests/SystemMetricsServiceTests.swift
git commit -m "feat: retain transiently stale metric samples"
```

### Task 3: Force Fresh Process Validation Before Quit Or Force Quit

**Files:**
- Modify: `Sources/MyMacStatsAppSupport/DashboardViewModel.swift:315-405`
- Modify: `Sources/MyMacStatsAppSupport/DashboardViewModel.swift:452-466`
- Test: `Tests/MyMacStatsAppSupportTests/DashboardViewModelTests.swift:197-461`
- Test support: `Tests/MyMacStatsAppSupportTests/DashboardViewModelTests.swift:550-586`

**Interfaces:**
- Consumes: `SystemMetricsService.refresh(now:reason:)` and `SystemMetricsSnapshot.processesAreFresh` from Tasks 1-2.
- Produces: scheduled refreshes that honor the selected interval and termination requests that fail closed on process sampling failure.

- [x] **Step 1: Write failing forced-refresh and fail-closed tests**

Make the existing `SnapshotSampler` mutable and observable:

```swift
@MainActor
private final class SnapshotSampler: SystemSampler {
    var processResult: [ProcessMetric]?
    private(set) var processCallCount = 0

    init(processes: [ProcessMetric]?) {
        processResult = processes
    }

    func sampleCPU() async -> CPUSnapshot? { nil }
    func sampleMemory() async -> MemorySnapshot? { nil }
    func sampleDisk() async -> DiskSnapshot? { nil }
    func sampleNetwork() async -> NetworkSnapshot? { nil }
    func sampleBattery() async -> BatterySnapshot? { nil }
    func sampleDiskSpaceCandidates() async -> [DiskSpaceCandidate] { [] }

    func sampleProcesses() async -> [ProcessMetric]? {
        processCallCount += 1
        return processResult
    }
}
```

Add the fail-closed behavior test:

```swift
func testTerminationDoesNotUseCachedProcessesWhenForcedRefreshFails() async {
    var sent: [(Int32, Int32)] = []
    let target = ProcessMetric(
        pid: 500,
        name: "Figma",
        cpuPercent: 10,
        memoryBytes: 100,
        path: "/Applications/Figma.app/Contents/MacOS/Figma",
        bundleIdentifier: "com.figma.Desktop"
    )
    let sampler = SnapshotSampler(processes: [target])
    let service = SystemMetricsService(
        sampler: sampler,
        evaluator: HealthEvaluator(debounceSamples: 1)
    )
    _ = await service.refresh(reason: .scheduled(baseInterval: 10))
    sampler.processResult = nil

    let viewModel = DashboardViewModel(
        snapshot: snapshot(processes: [target]),
        service: service,
        terminator: ProcessTerminator(
            currentProcessID: 99,
            signalSender: { pid, signal in
                sent.append((pid, signal))
                return 0
            },
            errnoProvider: { 0 }
        )
    )

    viewModel.requestTermination(for: target)
    await viewModel.confirmPendingTermination()

    XCTAssertEqual(sampler.processCallCount, 2)
    XCTAssertTrue(sent.isEmpty)
    XCTAssertEqual(
        viewModel.terminationMessage,
        "Could not refresh the process list. No termination signal was sent."
    )
}
```

Add a second test where the sampler still returns the target. Call a scheduled refresh immediately before confirmation and assert that confirmation increments `processCallCount` again despite the two-second cadence, then sends exactly one `SIGTERM`.

- [x] **Step 2: Run termination tests and verify RED**

Run:

```bash
swift test --filter DashboardViewModelTests/testTerminationDoesNotUseCachedProcessesWhenForcedRefreshFails
swift test --filter DashboardViewModelTests/testTerminationValidationForcesFreshProcessSampling
```

Expected: the first test fails because current confirmation cannot distinguish cached process data from a failed fresh sample; the second fails because confirmation does not yet use the explicit termination refresh reason.

- [x] **Step 3: Wire refresh reasons into the view model**

Change normal refresh to:

```swift
public func refreshNow() async {
    let refreshed = await service.refresh(
        reason: .scheduled(baseInterval: refreshInterval.seconds)
    )
    guard !Task.isCancelled else { return }
    snapshot = refreshed
    await healthAlertController.observe(snapshot: refreshed)
}
```

At the start of termination confirmation, use:

```swift
let latestSnapshot = await service.refresh(
    reason: .terminationValidation(baseInterval: refreshInterval.seconds)
)
snapshot = latestSnapshot
await healthAlertController.observe(snapshot: latestSnapshot)

guard latestSnapshot.processesAreFresh else {
    terminationMessage = "Could not refresh the process list. No termination signal was sent."
    terminationMessageProcessID = process.pid
    forceQuitCandidateGroupID = nil
    pendingTerminationProcess = nil
    pendingTerminationGroup = nil
    pendingTerminationMode = .quit
    return
}
```

Leave the existing PID/name/path/bundle comparison and protected-process checks unchanged after this guard.

In the loop, handle cancellation explicitly instead of swallowing it as an ordinary sleep result:

```swift
do {
    try await Task.sleep(for: .seconds(interval))
} catch is CancellationError {
    return
} catch {
    return
}
```

- [x] **Step 4: Run all termination and view-model tests**

Run:

```bash
swift test --filter DashboardViewModelTests
swift test --filter ProcessTerminatorTests
```

Expected: all selected tests pass; a failed process refresh sends neither `SIGTERM` nor `SIGKILL`.

- [x] **Step 5: Commit view-model safety wiring**

```bash
git add Sources/MyMacStatsAppSupport/DashboardViewModel.swift Tests/MyMacStatsAppSupportTests/DashboardViewModelTests.swift
git commit -m "fix: require fresh process data before termination"
```

### Task 4: Update Documentation And Perform Release Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/feature-verification-checklist-2026-08-04.md`
- Modify: `docs/superpowers/plans/2026-08-13-metric-refresh-reliability.md` only to mark completed checkboxes during execution.

**Interfaces:**
- Consumes: completed behavior from Tasks 1-3.
- Produces: accurate user documentation, updated verification evidence, release-ready personal build artifacts.

- [x] **Step 1: Update README behavior descriptions**

Document the effective cadence table, one-failure retained-value policy, two-failure unavailable transition, and forced process refresh before termination. Remove the limitation claiming that per-metric cadence and short last-known-good retention are not implemented.

- [x] **Step 2: Update the verification checklist**

Record the new test count only after the full suite runs. Mark metric cadence and last-known-good handling as verified, keep UI automation and real notification delivery as remaining limitations, and record that termination validation fails closed when fresh process sampling fails.

- [x] **Step 3: Run full clean verification**

Run:

```bash
swift package clean
swift test
swift build -c release
git diff --check
```

Expected: every command exits 0; XCTest reports zero failures.

- [x] **Step 4: Build and inspect the distributable app**

Run:

```bash
./scripts/build-app-bundle.sh
./scripts/check-distribution.sh dist/MyMacStats-test-build.zip
open dist/MyMacStats/MyMacStats.app
```

Confirm the app process starts, the dashboard displays populated metrics, and no privacy permission prompt appears.

- [x] **Step 5: Verify runtime cadence evidence**

Use the deterministic recording-sampler XCTest as the authoritative cadence proof. During the app smoke run, inspect process activity long enough to ensure the dashboard remains responsive; do not claim exact live `/bin/ps` call counts without instrumentation.

- [x] **Step 6: Commit documentation and checklist evidence**

```bash
git add README.md docs/feature-verification-checklist-2026-08-04.md docs/superpowers/plans/2026-08-13-metric-refresh-reliability.md
git commit -m "docs: document reliable metric refresh behavior"
```
