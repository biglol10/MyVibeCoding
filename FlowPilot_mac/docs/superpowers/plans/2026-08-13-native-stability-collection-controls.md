# Native macOS Stability and Collection Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent native macOS activity overcounting and silent data loss, harden the loopback browser bridge and SQLite writes, expose database failures, and add reversible collection pause/resume controls.

**Architecture:** Keep deterministic policies in `FlowPilotNativeCore` and keep AppKit, SwiftUI, timers, and `NWListener` wiring in `FlowPilotNative`. Add narrow core types for sampling continuity, manual collection state, HTTP request parsing, and HTTP response mapping; the executable target consumes those types without a concurrency rewrite.

**Tech Stack:** Swift 5.9, SwiftUI/AppKit, Network.framework, SQLite3, XCTest, existing Tauri/React/Rust and Chromium extension regression suites.

## Global Constraints

- Target the SwiftUI native macOS path first; do not change Tauri/Windows behavior unless regression compatibility requires it.
- Preserve the existing database path and schema compatibility; do not delete or rewrite user activity data.
- Use a 15-second maximum session merge gap, a 4 KiB header ceiling, a 16 KiB body ceiling, a 20 KiB total HTTP request ceiling, and a 2,000 ms SQLite busy timeout.
- Manual pause is in memory only; relaunching the app resumes collection unless the legacy Tauri app is running.
- Keep the collector on `@MainActor`; do not introduce the excluded background-worker refactor.
- The worktree already contains staged and unstaged user work, including the native app files as staged additions. Do not make implementation commits that would absorb those pre-existing changes. End each task with a scoped diff/status checkpoint and leave final commit ownership to the user.
- Do not overwrite generated release archives or install a new `/Applications/FlowPilot.app` during implementation.

---

### Task 1: Enforce Session Gaps and Define Manual Collection State

**Files:**

- Modify: `macos-native/Sources/FlowPilotNativeCore/Services/ActivitySessionAccumulator.swift`
- Create: `macos-native/Sources/FlowPilotNativeCore/Services/CollectionControlState.swift`
- Modify: `macos-native/Tests/FlowPilotNativeCoreTests/ActivitySessionAccumulatorTests.swift`
- Create: `macos-native/Tests/FlowPilotNativeCoreTests/CollectionControlStateTests.swift`

**Interfaces:**

- Produces: `ActivitySessionAccumulator.init(maximumMergeGap:idProvider:)`
- Produces: `ActivitySessionAccumulator.reset()`
- Produces: `CollectionControlState.isManuallyPaused`, `pause() -> Bool`, and `resume() -> Bool`
- Consumed by: Task 2 native collector wiring

- [ ] **Step 1: Write failing gap tests**

Add tests that catch the two overcounting mutations: ignoring a long/negative observation gap and retaining an open session after reset.

```swift
func testSplitsSameWindowAfterLongObservationGapWithoutCountingGap() {
    var ids = ["s1", "s2"]
    let accumulator = ActivitySessionAccumulator(
        maximumMergeGap: 15,
        idProvider: { ids.removeFirst() }
    )
    let start = Date(timeIntervalSince1970: 100)

    _ = accumulator.observe(sample(at: start, app: "Codex", title: "Project"))
    let records = accumulator.observe(
        sample(at: start.addingTimeInterval(16), app: "Codex", title: "Project")
    )

    XCTAssertEqual(records.map(\.id), ["s1", "s2"])
    XCTAssertEqual(records[0].durationSeconds, 1)
    XCTAssertEqual(records[1].durationSeconds, 1)
}

func testSplitsWhenObservationClockMovesBackward() {
    var ids = ["s1", "s2"]
    let accumulator = ActivitySessionAccumulator(
        maximumMergeGap: 15,
        idProvider: { ids.removeFirst() }
    )
    let start = Date(timeIntervalSince1970: 100)

    _ = accumulator.observe(sample(at: start, app: "Codex", title: "Project"))
    let records = accumulator.observe(
        sample(at: start.addingTimeInterval(-1), app: "Codex", title: "Project")
    )

    XCTAssertEqual(records.map(\.id), ["s1", "s2"])
    XCTAssertEqual(records[0].durationSeconds, 1)
}

func testResetPreventsSameWindowFromResumingPreviousSession() {
    var ids = ["s1", "s2"]
    let accumulator = ActivitySessionAccumulator(idProvider: { ids.removeFirst() })
    let start = Date(timeIntervalSince1970: 100)

    _ = accumulator.observe(sample(at: start, app: "Codex", title: "Project"))
    accumulator.reset()
    let records = accumulator.observe(
        sample(at: start.addingTimeInterval(5), app: "Codex", title: "Project")
    )

    XCTAssertEqual(records.map(\.id), ["s2"])
    XCTAssertEqual(records[0].durationSeconds, 1)
}
```

- [ ] **Step 2: Run the focused accumulator tests and verify RED**

Run:

```bash
swift test --package-path macos-native --filter ActivitySessionAccumulatorTests
```

Expected: compilation fails because `maximumMergeGap` and `reset()` do not exist. This is the intended failure, not a fixture or import failure.

- [ ] **Step 3: Implement the minimal gap policy**

Change the accumulator initializer and add an early discontinuity branch before the existing identity merge branch:

```swift
private let maximumMergeGap: TimeInterval

public init(
    maximumMergeGap: TimeInterval = 15,
    idProvider: @escaping IDProvider = { "active-window:\(UUID().uuidString)" }
) {
    self.maximumMergeGap = maximumMergeGap
    self.idProvider = idProvider
}

public func reset() {
    openSession = nil
}
```

In `observe(_:)`, immediately after unwrapping `openSession`, split discontinuous samples without using the new sample time to close the old record:

```swift
let observationGap = sample.observedAt.timeIntervalSince(openSession.sample.observedAt)
if observationGap < 0 || observationGap > maximumMergeGap {
    let closed = record(from: openSession, endedAt: openSession.sample.observedAt)
    let next = OpenSession(id: idProvider(), startedAt: sample.observedAt, sample: sample)
    self.openSession = next
    return [closed, record(from: next, endedAt: sample.observedAt)]
}
```

- [ ] **Step 4: Re-run accumulator tests and verify GREEN**

Run the focused test command again. Expected: all existing and new accumulator tests pass, including the existing exact 10-second merge behavior.

- [ ] **Step 5: Write failing collection-state tests**

Create `CollectionControlStateTests.swift`:

```swift
import XCTest
@testable import FlowPilotNativeCore

final class CollectionControlStateTests: XCTestCase {
    func testPauseAndResumeTransitionsAreIdempotent() {
        var state = CollectionControlState()

        XCTAssertTrue(state.pause())
        XCTAssertTrue(state.isManuallyPaused)
        XCTAssertFalse(state.pause())

        XCTAssertTrue(state.resume())
        XCTAssertFalse(state.isManuallyPaused)
        XCTAssertFalse(state.resume())
    }
}
```

Run:

```bash
swift test --package-path macos-native --filter CollectionControlStateTests
```

Expected: compilation fails because `CollectionControlState` is missing.

- [ ] **Step 6: Implement and verify collection state**

Create `CollectionControlState.swift`:

```swift
public struct CollectionControlState: Equatable {
    public private(set) var isManuallyPaused = false

    public init() {}

    @discardableResult
    public mutating func pause() -> Bool {
        guard !isManuallyPaused else { return false }
        isManuallyPaused = true
        return true
    }

    @discardableResult
    public mutating func resume() -> Bool {
        guard isManuallyPaused else { return false }
        isManuallyPaused = false
        return true
    }
}
```

Run both focused test classes. Expected: PASS.

- [ ] **Step 7: Record a scoped checkpoint**

Run:

```bash
git diff --check -- macos-native/Sources/FlowPilotNativeCore/Services/ActivitySessionAccumulator.swift macos-native/Sources/FlowPilotNativeCore/Services/CollectionControlState.swift macos-native/Tests/FlowPilotNativeCoreTests/ActivitySessionAccumulatorTests.swift macos-native/Tests/FlowPilotNativeCoreTests/CollectionControlStateTests.swift
git status --short -- macos-native/Sources/FlowPilotNativeCore/Services macos-native/Tests/FlowPilotNativeCoreTests
```

Expected: no whitespace errors; only the intended task files show new working-tree changes beyond their pre-existing staged state.

---

### Task 2: Wire Pause/Resume Into the Native Collector and UI

**Files:**

- Modify: `macos-native/Sources/FlowPilotNative/Collector/NativeActivityCollectorService.swift`
- Modify: `macos-native/Sources/FlowPilotNative/UI/AppShellView.swift`
- Modify: `macos-native/Sources/FlowPilotNative/FlowPilotNativeApp.swift`

**Interfaces:**

- Consumes: `CollectionControlState` and `ActivitySessionAccumulator.reset()` from Task 1
- Produces: `NativeActivityCollectorService.pauseCollection()`, `resumeCollection()`, `isManuallyPaused`, and `statusText`

- [ ] **Step 1: Add observable collector control behavior**

Add the state and derived presentation to `NativeActivityCollectorService`:

```swift
@Published private(set) var controlState = CollectionControlState()

var isManuallyPaused: Bool { controlState.isManuallyPaused }

var statusText: String {
    if lastError != nil { return "수집 오류" }
    if controlState.isManuallyPaused { return "사용자 일시정지" }
    if let pauseReason { return pauseReason }
    return isRunning ? "Swift 수집 중" : "수집 중지"
}
```

Extract timer setup so start and resume share one idempotent path and repeated `start()` calls cannot force an extra observation:

```swift
@discardableResult
private func scheduleTimerIfNeeded() -> Bool {
    guard timer == nil, !controlState.isManuallyPaused else { return false }
    isRunning = true
    timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.collectOnce() }
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
```

Add `guard !controlState.isManuallyPaused else { return }` at the beginning of `collectOnce()` so a queued callback cannot collect after pause.

- [ ] **Step 2: Build immediately to catch actor and access-control errors**

Run:

```bash
swift build --package-path macos-native
```

Expected: PASS with no new Swift warnings. If `statusText` exposes the full legacy explanation in a cramped sidebar, keep a separate concise label in the view rather than weakening `pauseReason` diagnostics.

- [ ] **Step 3: Add sidebar collection control**

Replace the current status-only footer in `AppShellView` with a status row plus control button:

```swift
VStack(alignment: .leading, spacing: 8) {
    HStack(spacing: 8) {
        Circle()
            .fill(collector.isRunning && collector.pauseReason == nil && !collector.isManuallyPaused ? .green : .gray)
            .frame(width: 8, height: 8)
        Text(collector.statusText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    Button(collector.isManuallyPaused ? "수집 재개" : "수집 일시정지") {
        if collector.isManuallyPaused {
            collector.resumeCollection()
        } else {
            collector.pauseCollection()
        }
    }
    .buttonStyle(.borderless)
}
.padding(.top, 12)
```

- [ ] **Step 4: Add menu-bar pause/resume control**

In `FlowPilotNativeApp`, render `collector.statusText` and add this button before `새로고침`:

```swift
Button(collector.isManuallyPaused ? "수집 재개" : "수집 일시정지") {
    if collector.isManuallyPaused {
        collector.resumeCollection()
    } else {
        collector.pauseCollection()
    }
}
```

- [ ] **Step 5: Verify compilation and Task 1 regression tests**

Run:

```bash
swift test --package-path macos-native --filter ActivitySessionAccumulatorTests
swift test --package-path macos-native --filter CollectionControlStateTests
swift build --package-path macos-native
```

Expected: all commands pass.

- [ ] **Step 6: Record a scoped checkpoint**

Run `git diff --check` for the three native executable files and inspect their scoped diff. Do not commit the pre-existing staged native application.

---

### Task 3: Add a Bounded, Crash-Safe Browser Bridge Parser

**Files:**

- Create: `macos-native/Sources/FlowPilotNativeCore/Services/BrowserBridgeRequestParser.swift`
- Create: `macos-native/Tests/FlowPilotNativeCoreTests/BrowserBridgeRequestParserTests.swift`

**Interfaces:**

- Produces: `BrowserBridgeRequestParser.parse(_:isComplete:) -> BrowserBridgeParseResult`
- Produces: `BrowserBridgeHTTPStatus` and `BrowserBridgeResponsePolicy.status(parseResult:persistenceSucceeded:)`
- Consumed by: Task 4 network service

- [ ] **Step 1: Write failing parser tests using real request bytes**

Create tests with a literal valid request and independently derived status expectations:

```swift
import XCTest
@testable import FlowPilotNativeCore

final class BrowserBridgeRequestParserTests: XCTestCase {
    func testAcceptsCompleteAuthenticatedJSONRequest() {
        let body = #"{"domain":"chatgpt.com","title":"ChatGPT"}"#
        let request = """
        POST /browser-event HTTP/1.1\r
        Content-Type: application/json; charset=utf-8\r
        X-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """

        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(Data(request.utf8), isComplete: false),
            .accepted(BrowserEventDraft(domain: "chatgpt.com", url: nil, title: "ChatGPT"))
        )
    }

    func testRejectsDuplicateHeadersWithoutTrapping() {
        let request = """
        POST /browser-event HTTP/1.1\r
        Content-Type: application/json\r
        Content-Type: application/json\r
        X-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r
        Content-Length: 2\r
        \r
        {}
        """

        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(Data(request.utf8), isComplete: true),
            .badRequest
        )
    }

    func testReturnsIncompleteUntilDeclaredBodyArrives() {
        let request = """
        POST /browser-event HTTP/1.1\r
        Content-Type: application/json\r
        X-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r
        Content-Length: 10\r
        \r
        {}
        """

        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(Data(request.utf8), isComplete: false),
            .incomplete
        )
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(Data(request.utf8), isComplete: true),
            .badRequest
        )
    }

    func testRejectsHeaderAndBodySizeLimits() {
        let oversizedHeader = "POST /browser-event HTTP/1.1\r\nX-Fill: \(String(repeating: "a", count: 4097))"
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(Data(oversizedHeader.utf8), isComplete: false),
            .payloadTooLarge
        )

        let body = String(repeating: "a", count: 16 * 1024 + 1)
        let oversizedBody = "POST /browser-event HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(Data(oversizedBody.utf8), isComplete: true),
            .payloadTooLarge
        )
    }

    func testPersistenceFailureMapsTo500InsteadOf204() {
        let draft = BrowserEventDraft(domain: "example.com", url: nil, title: "Example")

        XCTAssertEqual(
            BrowserBridgeResponsePolicy.status(
                parseResult: .accepted(draft),
                persistenceSucceeded: false
            ),
            .internalServerError
        )
        XCTAssertEqual(
            BrowserBridgeResponsePolicy.status(
                parseResult: .accepted(draft),
                persistenceSucceeded: true
            ),
            .noContent
        )
    }
}
```

Add this table-driven test for the remaining protocol branches:

```swift
func testMapsInvalidProtocolRequestsToSpecificClientErrors() {
    let cases: [(String, BrowserBridgeParseResult)] = [
        (
            "GET /browser-event HTTP/1.1\r\nContent-Length: 0\r\n\r\n",
            .methodNotAllowed
        ),
        (
            "POST /wrong HTTP/1.1\r\nContent-Length: 0\r\n\r\n",
            .notFound
        ),
        (
            "POST /browser-event HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}",
            .forbidden
        ),
        (
            "POST /browser-event HTTP/1.1\r\nContent-Type: text/plain\r\nX-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r\nContent-Length: 2\r\n\r\n{}",
            .forbidden
        ),
        (
            "POST /browser-event HTTP/1.1\r\nContent-Type: application/json\r\nX-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r\nContent-Length: 1\r\n\r\n{",
            .badRequest
        ),
        (
            "POST /browser-event HTTP/1.1\r\nContent-Type: application/json\r\nX-FlowPilot-Bridge: flowpilot-browser-bridge-v1\r\nContent-Length: 2\r\n\r\n{}extra",
            .badRequest
        )
    ]

    for (request, expected) in cases {
        XCTAssertEqual(
            BrowserBridgeRequestParser.parse(Data(request.utf8), isComplete: true),
            expected
        )
    }
}
```

- [ ] **Step 2: Run parser tests and verify RED**

Run:

```bash
swift test --package-path macos-native --filter BrowserBridgeRequestParserTests
```

Expected: compilation fails because the parser and response policy do not exist.

- [ ] **Step 3: Implement the parser contracts**

Create these public result types:

```swift
public enum BrowserBridgeParseResult: Equatable {
    case accepted(BrowserEventDraft)
    case incomplete
    case badRequest
    case forbidden
    case methodNotAllowed
    case notFound
    case payloadTooLarge
}

public enum BrowserBridgeHTTPStatus: Int, Equatable {
    case noContent = 204
    case badRequest = 400
    case forbidden = 403
    case notFound = 404
    case methodNotAllowed = 405
    case payloadTooLarge = 413
    case internalServerError = 500
}
```

Implement `BrowserBridgeRequestParser` with:

```swift
public static let maximumHeaderBytes = 4 * 1024
public static let maximumBodyBytes = 16 * 1024
public static let maximumRequestBytes = maximumHeaderBytes + maximumBodyBytes

public static func parse(_ data: Data, isComplete: Bool) -> BrowserBridgeParseResult
```

The implementation must locate `\r\n\r\n` in `Data`, reject a header section over 4 KiB, require a non-negative integer `Content-Length`, reject duplicate lowercase header names before insertion, require body size to equal `Content-Length`, decode only the body bytes, and return `.incomplete` only while more bytes can still produce a valid request. Map parse results with:

```swift
public enum BrowserBridgeResponsePolicy {
    public static func status(
        parseResult: BrowserBridgeParseResult,
        persistenceSucceeded: Bool? = nil
    ) -> BrowserBridgeHTTPStatus? {
        switch parseResult {
        case .accepted:
            guard let persistenceSucceeded else { return nil }
            return persistenceSucceeded ? .noContent : .internalServerError
        case .incomplete:
            return nil
        case .badRequest:
            return .badRequest
        case .forbidden:
            return .forbidden
        case .methodNotAllowed:
            return .methodNotAllowed
        case .notFound:
            return .notFound
        case .payloadTooLarge:
            return .payloadTooLarge
        }
    }
}
```

- [ ] **Step 4: Run parser tests and verify GREEN**

Run the focused parser suite. Expected: all parser and response-policy cases pass without opening a network listener or using mocks.

- [ ] **Step 5: Run full native core tests**

Run:

```bash
swift test --package-path macos-native
```

Expected: all baseline tests plus the new parser tests pass.

- [ ] **Step 6: Record a scoped checkpoint**

Run `git diff --check` and inspect only the new parser and parser-test files.

---

### Task 4: Integrate Parser, Truthful Responses, and Bridge Retry

**Files:**

- Modify: `macos-native/Sources/FlowPilotNative/Collector/NativeBrowserBridgeService.swift`
- Modify: `macos-native/Sources/FlowPilotNative/UI/TodayView.swift`

**Interfaces:**

- Consumes: Task 3 parser, result, response policy, and status types
- Produces: `NativeBrowserBridgeService.restart()`

- [ ] **Step 1: Replace the executable-target parser with the core parser**

In `receive(on:accumulated:)`, append the new data, parse it with the callback's `isComplete`, and branch on the core result:

```swift
let parseResult = BrowserBridgeRequestParser.parse(next, isComplete: isComplete)
switch parseResult {
case .incomplete:
    receive(on: connection, accumulated: next)
case .accepted(let draft):
    Task { @MainActor in
        do {
            try self.database.saveBrowserEvent(draft)
            self.lastError = nil
            let status = BrowserBridgeResponsePolicy.status(
                parseResult: .accepted(draft),
                persistenceSucceeded: true
            ) ?? .internalServerError
            self.send(status: status, on: connection)
        } catch {
            self.lastError = error.localizedDescription
            let status = BrowserBridgeResponsePolicy.status(
                parseResult: .accepted(draft),
                persistenceSucceeded: false
            ) ?? .internalServerError
            self.send(status: status, on: connection)
        }
    }
default:
    guard let status = BrowserBridgeResponsePolicy.status(parseResult: parseResult) else {
        self.send(status: .badRequest, on: connection)
        return
    }
    send(status: status, on: connection)
}
```

Delete the old `response(for:)` dictionary construction and `BrowserBridgeHTTPResponse.accepted` path. Render a response from `BrowserBridgeHTTPStatus.rawValue`, adding `500 Internal Server Error` to the reason phrases.

- [ ] **Step 2: Make listener lifecycle restartable**

Handle failure on the main actor:

```swift
case .failed(let error):
    self?.listener = nil
    self?.isRunning = false
    self?.lastError = error.localizedDescription
```

Expose:

```swift
func restart() {
    stop()
    lastError = nil
    start()
}
```

For `.waiting(let error)`, keep the listener so Network.framework may recover, but set `isRunning = false` and expose the error. The retry button calls `restart()` to replace a waiting listener explicitly.

- [ ] **Step 3: Build to verify parser integration**

Run:

```bash
swift build --package-path macos-native
swift test --package-path macos-native --filter BrowserBridgeRequestParserTests
```

Expected: both pass; no private parser remains in the executable target.

- [ ] **Step 4: Add the bridge retry action to Today**

Change `browserBridgeError` to retain the error text and show a button only while the listener is not ready:

```swift
VStack(alignment: .leading, spacing: 8) {
    Text("브라우저 브리지: \(error)")
    if !browserBridge.isRunning {
        Button("브리지 다시 시도") {
            browserBridge.restart()
        }
    }
}
```

Keep the existing orange styling and full-width alignment.

- [ ] **Step 5: Verify a real loopback request**

Build and launch the development app. Verify port `17321` accepts a TCP connection, then send a duplicate-header request and verify HTTP 400 without an app crash; this path performs no database write. Do not send an accepted live event to the user's database. HTTP 204-after-save and HTTP 500-on-save-failure are proved by the response-policy unit test and by the executable integration branch compiled in Step 3.

- [ ] **Step 6: Record a scoped checkpoint**

Run `git diff --check` for the bridge service and Today view, then inspect their scoped diff.

---

### Task 5: Add SQLite Busy Waiting and Atomic Multi-Row Writes

**Files:**

- Modify: `macos-native/Sources/FlowPilotNativeCore/Services/FlowPilotDatabase.swift`
- Modify: `macos-native/Tests/FlowPilotNativeCoreTests/FlowPilotDatabaseTests.swift`

**Interfaces:**

- Preserves all existing public `FlowPilotDatabase` methods
- Adds only private `withTransaction` behavior and connection configuration

- [ ] **Step 1: Write a failing transaction rollback test**

Create a session, install a test-only SQLite trigger that aborts the second observation, call the real multi-row method, and assert no observation committed:

```swift
func testWindowObservationBatchRollsBackWhenLaterInsertFails() throws {
    let databaseURL = temporaryDatabaseURL()
    let database = FlowPilotDatabase(path: databaseURL.path)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let session = testSession(id: "atomic-session", at: now)
    try database.saveSessions([session])
    try withWritableDatabase(databaseURL) { db in
        try execute(db, """
            CREATE TRIGGER fail_bad_observation
            BEFORE INSERT ON window_observations
            WHEN NEW.app_name = 'Fail'
            BEGIN
              SELECT RAISE(ABORT, 'forced failure');
            END;
            """)
    }

    let observations = [
        testObservation(appName: "Good", at: now),
        testObservation(appName: "Fail", at: now)
    ]

    XCTAssertThrowsError(
        try database.saveWindowObservations(sessionID: session.id, observations: observations)
    )
    try withWritableDatabase(databaseURL) { db in
        XCTAssertEqual(try intValue(db, "SELECT COUNT(*) FROM window_observations"), 0)
    }
}
```

Keep `testSession` and `testObservation` as private test helpers returning complete real model values.

```swift
private func testSession(id: String, at date: Date) -> ActivitySessionRecord {
    ActivitySessionRecord(
        id: id,
        startedAt: date,
        endedAt: date.addingTimeInterval(5),
        durationSeconds: 5,
        appName: "Codex",
        processName: "Codex",
        windowTitle: "Project",
        domain: nil,
        url: nil,
        isIdle: false
    )
}

private func testObservation(appName: String, at date: Date) -> WindowObservationRecord {
    WindowObservationRecord(
        observedAt: date,
        appName: appName,
        processName: appName,
        pid: 42,
        bundleIdentifier: "com.example.\(appName.lowercased())",
        windowTitle: appName,
        isVisible: true,
        isFrontmost: appName == "Good",
        isPrimary: appName == "Good"
    )
}
```

- [ ] **Step 2: Run the rollback test and verify RED**

Run:

```bash
swift test --package-path macos-native --filter testWindowObservationBatchRollsBackWhenLaterInsertFails
```

Expected: FAIL because the first observation remains committed.

- [ ] **Step 3: Add transaction handling**

Add:

```swift
private static func withTransaction<T>(
    db: OpaquePointer,
    _ body: () throws -> T
) throws -> T {
    try execute(db: db, sql: "BEGIN IMMEDIATE")
    do {
        let value = try body()
        try execute(db: db, sql: "COMMIT")
        return value
    } catch {
        try? execute(db: db, sql: "ROLLBACK")
        throw error
    }
}
```

Wrap the prune-and-insert loop in `saveWindowObservations` and the insert loop in `saveSessions`. Keep `initializeSchema` before `BEGIN IMMEDIATE` so schema setup is not coupled to a sample batch.

- [ ] **Step 4: Verify rollback GREEN**

Re-run the focused rollback test. Expected: PASS and the row count is exactly zero.

- [ ] **Step 5: Write a failing short-contention test**

Open a second SQLite connection, begin an immediate transaction, start a real `saveSessions` call on a utility queue, release the lock after 100 ms, and assert the save succeeds before a two-second expectation timeout. Instantiate `FlowPilotDatabase` inside the queue using only the database path to avoid sharing a non-Sendable connection.

```swift
func testWriteWaitsForBriefSQLiteContention() throws {
    let databaseURL = temporaryDatabaseURL()
    let database = FlowPilotDatabase(path: databaseURL.path)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    try database.saveSessions([testSession(id: "seed", at: now)])

    var lockDB: OpaquePointer?
    XCTAssertEqual(sqlite3_open(databaseURL.path, &lockDB), SQLITE_OK)
    guard let lockDB else { return }
    defer { sqlite3_close(lockDB) }
    try execute(lockDB, "BEGIN IMMEDIATE")

    let saved = expectation(description: "write waited for lock")
    let path = databaseURL.path
    DispatchQueue.global(qos: .utility).async {
        do {
            try FlowPilotDatabase(path: path).saveSessions([
                self.testSession(id: "after-lock", at: now.addingTimeInterval(5))
            ])
            saved.fulfill()
        } catch {
            XCTFail("Unexpected lock failure: \(error)")
        }
    }

    Thread.sleep(forTimeInterval: 0.1)
    try execute(lockDB, "COMMIT")
    wait(for: [saved], timeout: 2)
}
```

If XCTest reports a concurrency warning for calling an instance helper from the queue, construct the literal `ActivitySessionRecord` before dispatch and capture that immutable value instead.

- [ ] **Step 6: Add and validate the busy timeout**

Immediately after a connection opens successfully in `withConnection`, call:

```swift
let busyResult = sqlite3_busy_timeout(db, 2_000)
guard busyResult == SQLITE_OK else {
    throw FlowPilotDatabaseError.openFailed(String(cString: sqlite3_errmsg(db)))
}
```

Run the focused contention test and the full `FlowPilotDatabaseTests`. Expected: PASS without waiting the full two seconds.

- [ ] **Step 7: Record a scoped checkpoint**

Run `git diff --check`, inspect the two scoped files, and confirm no schema or database-path change appears.

---

### Task 6: Preserve Last Good Reports and Surface Database Errors

**Files:**

- Modify: `macos-native/Sources/FlowPilotNativeCore/Services/FlowPilotReportStore.swift`
- Create: `macos-native/Tests/FlowPilotNativeCoreTests/FlowPilotReportStoreTests.swift`
- Modify: `macos-native/Sources/FlowPilotNative/UI/TodayView.swift`

**Interfaces:**

- Preserves `FlowPilotReportStore.refresh(now:)`
- Adds private `hasLoadedDatabaseData`
- Consumed by: Today error banner and retry button

- [ ] **Step 1: Write failing missing-versus-corrupt database tests**

Create `FlowPilotReportStoreTests.swift`:

```swift
import XCTest
@testable import FlowPilotNativeCore

final class FlowPilotReportStoreTests: XCTestCase {
    func testMissingDatabaseUsesOrdinarySampleDataWithoutError() {
        let url = temporaryURL()

        let store = FlowPilotReportStore(databaseURL: url)

        XCTAssertEqual(store.dataSourceLabel, "샘플 데이터")
        XCTAssertNil(store.lastError)
    }

    func testUnreadableExistingDatabaseLabelsFallbackAsError() throws {
        let url = temporaryURL()
        try Data("not a sqlite database".utf8).write(to: url)

        let store = FlowPilotReportStore(databaseURL: url)

        XCTAssertEqual(store.dataSourceLabel, "샘플 데이터 (데이터베이스 오류)")
        XCTAssertNotNil(store.lastError)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("flowpilot-report-store-\(UUID().uuidString)")
            .appendingPathExtension("sqlite3")
    }
}
```

The test catches the current bug where `applyFallback()` overwrites the source label and visually hides the error.

- [ ] **Step 2: Run report-store tests and verify RED**

Run:

```bash
swift test --package-path macos-native --filter FlowPilotReportStoreTests
```

Expected: the missing-file test passes and the corrupt-file label test fails with `샘플 데이터`.

- [ ] **Step 3: Separate ordinary fallback from error fallback**

Add `private var hasLoadedDatabaseData = false`. On successful refresh, set it to true. On missing file, call `applyFallback(label: "샘플 데이터")` and set `lastError = nil`. On catch:

```swift
lastError = error.localizedDescription
if hasLoadedDatabaseData {
    dataSourceLabel = "마지막 정상 데이터 (데이터베이스 오류)"
} else {
    applyFallback(label: "샘플 데이터 (데이터베이스 오류)")
}
```

Change the helper signature to `private func applyFallback(label: String)` and assign the supplied label. Do not clear `lastError` inside this helper.

- [ ] **Step 4: Add last-good-data and recovery tests**

Add this test and helper to `FlowPilotReportStoreTests.swift`:

```swift
func testRefreshKeepsLastGoodDataAndClearsErrorAfterRecovery() throws {
    let url = temporaryURL()
    let now = Date()
    let firstSession = session(id: "first", at: now.addingTimeInterval(-60))
    try FlowPilotDatabase(path: url.path).saveSessions([firstSession])
    let store = FlowPilotReportStore(databaseURL: url)
    XCTAssertEqual(store.summary.sessionCount, 1)

    try FileManager.default.removeItem(at: url)
    try Data("not a sqlite database".utf8).write(to: url)
    store.refresh(now: now)

    XCTAssertEqual(store.summary.sessionCount, 1)
    XCTAssertEqual(store.dataSourceLabel, "마지막 정상 데이터 (데이터베이스 오류)")
    XCTAssertNotNil(store.lastError)

    try FileManager.default.removeItem(at: url)
    let recoveredSession = session(id: "recovered", at: now.addingTimeInterval(-30))
    try FlowPilotDatabase(path: url.path).saveSessions([recoveredSession])
    store.refresh(now: now)

    XCTAssertEqual(store.summary.sessionCount, 1)
    XCTAssertEqual(store.dataSourceLabel, "기존 FlowPilot 데이터")
    XCTAssertNil(store.lastError)
}

private func session(id: String, at date: Date) -> ActivitySessionRecord {
    ActivitySessionRecord(
        id: id,
        startedAt: date,
        endedAt: date.addingTimeInterval(5),
        durationSeconds: 5,
        appName: "Codex",
        processName: "Codex",
        windowTitle: "Project",
        domain: nil,
        url: nil,
        isIdle: false
    )
}
```

Run the focused suite. Expected: all report-store tests pass.

- [ ] **Step 5: Add the Today database error banner**

Render `reportStoreError` after the pause notice and before collector/bridge errors:

```swift
@ViewBuilder
private var reportStoreError: some View {
    if let error = store.lastError {
        VStack(alignment: .leading, spacing: 8) {
            Text("데이터를 읽는 중 문제가 발생했습니다")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("데이터 다시 읽기") {
                store.refresh()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.red.opacity(0.25)))
    }
}
```

- [ ] **Step 6: Verify report and native build tests**

Run:

```bash
swift test --package-path macos-native --filter FlowPilotReportStoreTests
swift test --package-path macos-native --filter FlowPilotDatabaseTests
swift build --package-path macos-native
```

Expected: all pass.

- [ ] **Step 7: Record a scoped checkpoint**

Run `git diff --check` and inspect only the store, store tests, and Today view.

---

### Task 7: Full Regression and Actual macOS Runtime Verification

**Files:**

- Verify only: all files changed in Tasks 1–6
- Verify only: root frontend, browser extension, Tauri Rust, and native Swift suites

**Interfaces:**

- Consumes all prior tasks
- Produces no new behavior; this task establishes the evidence boundary for handoff

- [ ] **Step 1: Run the complete native suite and release build**

Run:

```bash
swift test --package-path macos-native
swift build -c release --package-path macos-native
```

Expected: every native test passes with zero failures and the release executable links successfully.

- [ ] **Step 2: Run cross-platform regression suites**

Run:

```bash
npm test
npm run build
npm test --prefix browser-extension
npm run build --prefix browser-extension
npm run e2e
cargo test --manifest-path src-tauri/Cargo.toml
```

Expected: match or improve the baseline—69 frontend tests, 10 script tests, 6 extension tests, 65 Rust tests, and 5 passing Playwright cases with the existing 1 desktop skip. The frontend large-chunk warning may remain and must be reported as unchanged.

- [ ] **Step 3: Rebuild the development app without packaging or installation**

Run:

```bash
macos-native/scripts/build-dev-app.sh
```

Expected: the ad-hoc-signed development app is created at `macos-native/.build/FlowPilotNative.app`. Do not run personal ZIP/DMG scripts and do not replace `/Applications/FlowPilot.app`.

- [ ] **Step 4: Verify the actual native UI**

Open the development app and verify:

1. Today, Timeline, Weekly Report, Uncategorized Review, and Rules all render.
2. Sidebar status begins as active unless the legacy Tauri app is running.
3. `수집 일시정지` changes the status to `사용자 일시정지` and the menu item becomes `수집 재개`.
4. Resume immediately starts a fresh collection boundary; the paused interval is absent from the next session.
5. The menu-bar control performs the same transition without creating a duplicate timer.
6. A bridge error presents `브리지 다시 시도`; a report error presents `데이터 다시 읽기`.

Close the development app after verification. Do not grant new macOS privacy permissions during this check.

- [ ] **Step 5: Audit the final working tree**

Run:

```bash
git diff --check
git status --short
git diff -- macos-native/Sources/FlowPilotNativeCore macos-native/Sources/FlowPilotNative macos-native/Tests/FlowPilotNativeCoreTests
```

Confirm every modified path belongs to the approved design, no release archive changed, and no unrelated user change was reverted or committed.

- [ ] **Step 6: Report verified scope and remaining boundaries**

Report exact test counts and build results. State explicitly that local tests and a short UI run do not prove long-running energy use, every macOS permission configuration, Developer ID signing, notarization, or public distribution readiness.
