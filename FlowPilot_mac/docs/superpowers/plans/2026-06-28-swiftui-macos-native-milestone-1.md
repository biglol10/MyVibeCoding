# SwiftUI macOS Native Milestone 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a buildable native SwiftUI macOS FlowPilot app skeleton without breaking the existing Tauri/React/Rust app.

**Architecture:** Create a separate Swift Package under `macos-native/` so the native app can evolve independently from the current cross-platform app. The first milestone uses sample report data and native SwiftUI views that mirror the existing FlowPilot navigation and report concepts. Existing Tauri, React, Rust, browser extension, Windows artifacts, and packaging scripts remain unchanged.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit activation hooks, Swift Package Manager, XCTest.

---

### Task 1: Swift Package Skeleton

**Files:**
- Create: `macos-native/Package.swift`
- Create: `macos-native/Sources/FlowPilotNative/FlowPilotNativeApp.swift`
- Create: `macos-native/Tests/FlowPilotNativeTests/PlaceholderTests.swift`

- [ ] **Step 1: Add Swift package manifest**

Create `macos-native/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlowPilotNative",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FlowPilotNative", targets: ["FlowPilotNative"])
    ],
    targets: [
        .executableTarget(
            name: "FlowPilotNative",
            path: "Sources/FlowPilotNative"
        ),
        .testTarget(
            name: "FlowPilotNativeTests",
            dependencies: ["FlowPilotNative"],
            path: "Tests/FlowPilotNativeTests"
        )
    ]
)
```

- [ ] **Step 2: Add minimal SwiftUI app entrypoint**

Create `macos-native/Sources/FlowPilotNative/FlowPilotNativeApp.swift`:

```swift
import SwiftUI

@main
struct FlowPilotNativeApp: App {
    var body: some Scene {
        WindowGroup("FlowPilot") {
            Text("FlowPilot")
                .frame(minWidth: 960, minHeight: 680)
        }
    }
}
```

- [ ] **Step 3: Add placeholder XCTest**

Create `macos-native/Tests/FlowPilotNativeTests/PlaceholderTests.swift`:

```swift
import XCTest

final class PlaceholderTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 4: Verify package builds**

Run:

```bash
cd macos-native
swift test
```

Expected: test succeeds with 1 passing test.

### Task 2: Native Data Model And Formatting

**Files:**
- Create: `macos-native/Sources/FlowPilotNative/Model/ActivityCategory.swift`
- Create: `macos-native/Sources/FlowPilotNative/Model/ReportModels.swift`
- Create: `macos-native/Sources/FlowPilotNative/Services/DurationFormatting.swift`
- Create: `macos-native/Tests/FlowPilotNativeTests/DurationFormattingTests.swift`
- Replace: `macos-native/Tests/FlowPilotNativeTests/PlaceholderTests.swift`

- [ ] **Step 1: Write duration formatting tests**

Create `macos-native/Tests/FlowPilotNativeTests/DurationFormattingTests.swift`:

```swift
import XCTest
@testable import FlowPilotNative

final class DurationFormattingTests: XCTestCase {
    func testFormatsZeroSecondsAsZeroMinutes() {
        XCTAssertEqual(DurationFormatting.compact(seconds: 0), "0m")
    }

    func testFormatsSubMinuteAsLessThanOneMinute() {
        XCTAssertEqual(DurationFormatting.compact(seconds: 25), "<1m")
    }

    func testFormatsMinutes() {
        XCTAssertEqual(DurationFormatting.compact(seconds: 17 * 60), "17m")
    }

    func testFormatsHoursAndMinutes() {
        XCTAssertEqual(DurationFormatting.compact(seconds: 3 * 3600 + 15 * 60), "3h 15m")
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd macos-native
swift test
```

Expected: failure because `DurationFormatting` does not exist yet.

- [ ] **Step 3: Add category and report models**

Create `macos-native/Sources/FlowPilotNative/Model/ActivityCategory.swift`:

```swift
import SwiftUI

enum ActivityCategory: String, CaseIterable, Identifiable {
    case productive
    case unproductive
    case neutral
    case ignored
    case uncategorized
    case idle

    var id: String { rawValue }

    var koreanLabel: String {
        switch self {
        case .productive: return "생산적"
        case .unproductive: return "비생산"
        case .neutral: return "중립"
        case .ignored: return "제외"
        case .uncategorized: return "검토 필요"
        case .idle: return "유휴"
        }
    }

    var color: Color {
        switch self {
        case .productive: return .green
        case .unproductive: return .red
        case .neutral: return .blue
        case .ignored: return .gray
        case .uncategorized: return .purple
        case .idle: return .secondary
        }
    }
}
```

Create `macos-native/Sources/FlowPilotNative/Model/ReportModels.swift`:

```swift
import Foundation

struct DashboardSummary: Equatable {
    let totalSeconds: Int
    let productiveSeconds: Int
    let unproductiveSeconds: Int
    let idleSeconds: Int
    let sessionCount: Int
}

struct UsageItem: Identifiable, Equatable {
    let id: UUID
    let name: String
    let kind: String
    let category: ActivityCategory
    let durationSeconds: Int
    let share: Double
    let ruleSource: String
}

struct TimelineSession: Identifiable, Equatable {
    let id: UUID
    let name: String
    let title: String?
    let category: ActivityCategory
    let startedAt: Date
    let endedAt: Date

    var durationSeconds: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }
}
```

- [ ] **Step 4: Add formatter implementation**

Create `macos-native/Sources/FlowPilotNative/Services/DurationFormatting.swift`:

```swift
enum DurationFormatting {
    static func compact(seconds: Int) -> String {
        if seconds <= 0 {
            return "0m"
        }
        if seconds < 60 {
            return "<1m"
        }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
```

- [ ] **Step 5: Remove placeholder test**

Delete `macos-native/Tests/FlowPilotNativeTests/PlaceholderTests.swift`.

- [ ] **Step 6: Verify tests pass**

Run:

```bash
cd macos-native
swift test
```

Expected: 4 tests pass.

### Task 3: Sample Report Store

**Files:**
- Create: `macos-native/Sources/FlowPilotNative/Services/SampleReportStore.swift`
- Create: `macos-native/Tests/FlowPilotNativeTests/SampleReportStoreTests.swift`

- [ ] **Step 1: Write report store tests**

Create `macos-native/Tests/FlowPilotNativeTests/SampleReportStoreTests.swift`:

```swift
import XCTest
@testable import FlowPilotNative

final class SampleReportStoreTests: XCTestCase {
    func testSummaryMatchesUsageItems() {
        let store = SampleReportStore()

        XCTAssertEqual(store.summary.totalSeconds, store.usageItems.map(\.durationSeconds).reduce(0, +))
        XCTAssertEqual(store.summary.sessionCount, store.timelineSessions.count)
        XCTAssertGreaterThan(store.summary.productiveSeconds, 0)
    }

    func testTopUsageIsSortedByDurationDescending() {
        let store = SampleReportStore()
        let durations = store.usageItems.map(\.durationSeconds)

        XCTAssertEqual(durations, durations.sorted(by: >))
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd macos-native
swift test
```

Expected: failure because `SampleReportStore` does not exist yet.

- [ ] **Step 3: Add sample report store**

Create `macos-native/Sources/FlowPilotNative/Services/SampleReportStore.swift`:

```swift
import Foundation

@Observable
final class SampleReportStore {
    let summary: DashboardSummary
    let usageItems: [UsageItem]
    let timelineSessions: [TimelineSession]

    init(now: Date = Date()) {
        let calendar = Calendar.current
        let start = calendar.date(bySettingHour: 9, minute: 20, second: 0, of: now) ?? now

        self.usageItems = [
            UsageItem(id: UUID(), name: "Codex", kind: "앱", category: .productive, durationSeconds: 6420, share: 0.55, ruleSource: "사용자 규칙"),
            UsageItem(id: UUID(), name: "capturestudio.app", kind: "앱", category: .uncategorized, durationSeconds: 4200, share: 0.36, ruleSource: "규칙 없음"),
            UsageItem(id: UUID(), name: "chatgpt.com", kind: "도메인", category: .productive, durationSeconds: 1080, share: 0.09, ruleSource: "기본 규칙")
        ]

        self.timelineSessions = [
            TimelineSession(id: UUID(), name: "Codex", title: "FlowPilot 작업", category: .productive, startedAt: start, endedAt: start.addingTimeInterval(2940)),
            TimelineSession(id: UUID(), name: "capturestudio.app", title: "화면 캡처", category: .uncategorized, startedAt: start.addingTimeInterval(2940), endedAt: start.addingTimeInterval(7140)),
            TimelineSession(id: UUID(), name: "chatgpt.com", title: "SwiftUI 설계", category: .productive, startedAt: start.addingTimeInterval(7140), endedAt: start.addingTimeInterval(8220))
        ]

        let total = usageItems.map(\.durationSeconds).reduce(0, +)
        let productive = usageItems.filter { $0.category == .productive }.map(\.durationSeconds).reduce(0, +)
        let unproductive = usageItems.filter { $0.category == .unproductive }.map(\.durationSeconds).reduce(0, +)
        let idle = usageItems.filter { $0.category == .idle }.map(\.durationSeconds).reduce(0, +)

        self.summary = DashboardSummary(
            totalSeconds: total,
            productiveSeconds: productive,
            unproductiveSeconds: unproductive,
            idleSeconds: idle,
            sessionCount: timelineSessions.count
        )
    }
}
```

- [ ] **Step 4: Verify tests pass**

Run:

```bash
cd macos-native
swift test
```

Expected: 6 tests pass.

### Task 4: SwiftUI Shell

**Files:**
- Replace: `macos-native/Sources/FlowPilotNative/FlowPilotNativeApp.swift`
- Create: `macos-native/Sources/FlowPilotNative/UI/AppShellView.swift`
- Create: `macos-native/Sources/FlowPilotNative/UI/TodayView.swift`
- Create: `macos-native/Sources/FlowPilotNative/UI/TimelineView.swift`
- Create: `macos-native/Sources/FlowPilotNative/UI/WeeklyReportView.swift`
- Create: `macos-native/Sources/FlowPilotNative/UI/ReviewView.swift`
- Create: `macos-native/Sources/FlowPilotNative/UI/RulesView.swift`

- [ ] **Step 1: Replace app entrypoint with shared store**

Update `macos-native/Sources/FlowPilotNative/FlowPilotNativeApp.swift`:

```swift
import SwiftUI

@main
struct FlowPilotNativeApp: App {
    @State private var reportStore = SampleReportStore()

    var body: some Scene {
        WindowGroup("FlowPilot") {
            AppShellView()
                .environment(reportStore)
                .frame(minWidth: 960, minHeight: 680)
        }

        MenuBarExtra("FlowPilot", systemImage: "paperplane.circle.fill") {
            Text("오늘 기록 \(DurationFormatting.compact(seconds: reportStore.summary.totalSeconds))")
            Text("생산적 \(DurationFormatting.compact(seconds: reportStore.summary.productiveSeconds))")
            Divider()
            Button("FlowPilot 열기") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("종료") {
                NSApp.terminate(nil)
            }
        }
    }
}
```

- [ ] **Step 2: Add shell view**

Create `macos-native/Sources/FlowPilotNative/UI/AppShellView.swift`:

```swift
import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
    case today
    case timeline
    case weekly
    case review
    case rules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "오늘 요약"
        case .timeline: return "타임라인"
        case .weekly: return "주간 리포트"
        case .review: return "미분류 검토"
        case .rules: return "분류 규칙"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "square.grid.2x2"
        case .timeline: return "clock"
        case .weekly: return "chart.bar"
        case .review: return "tray"
        case .rules: return "slider.horizontal.3"
        }
    }
}

struct AppShellView: View {
    @State private var selection: NavigationItem? = .today

    var body: some View {
        NavigationSplitView {
            List(NavigationItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol)
            }
            .navigationTitle("FlowPilot")
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("기록 중")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        } detail: {
            switch selection ?? .today {
            case .today: TodayView()
            case .timeline: TimelineView()
            case .weekly: WeeklyReportView()
            case .review: ReviewView()
            case .rules: RulesView()
            }
        }
    }
}
```

- [ ] **Step 3: Add Today view**

Create `macos-native/Sources/FlowPilotNative/UI/TodayView.swift`:

```swift
import SwiftUI

struct TodayView: View {
    @Environment(SampleReportStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                summaryGrid
                usageTable
            }
            .padding(28)
        }
        .navigationTitle("오늘 요약")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("활동 분석")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("오늘 요약")
                    .font(.largeTitle.bold())
            }
            Spacer()
            Text("\(store.summary.sessionCount)개 세션")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
        }
    }

    private var summaryGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                metric("총 기록 시간", store.summary.totalSeconds)
                metric("생산적 사용", store.summary.productiveSeconds)
            }
            GridRow {
                metric("비생산 사용", store.summary.unproductiveSeconds)
                metric("유휴 시간", store.summary.idleSeconds)
            }
        }
    }

    private func metric(_ title: String, _ seconds: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(DurationFormatting.compact(seconds: seconds))
                .font(.title.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }

    private var usageTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("상위 사용 항목")
                .font(.title2.bold())
            ForEach(store.usageItems) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.name).font(.headline)
                        Text(item.ruleSource).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(item.category.koreanLabel)
                        .foregroundStyle(item.category.color)
                    Text(DurationFormatting.compact(seconds: item.durationSeconds))
                        .font(.headline)
                        .frame(width: 80, alignment: .trailing)
                }
                Divider()
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }
}
```

- [ ] **Step 4: Add Timeline view**

Create `macos-native/Sources/FlowPilotNative/UI/TimelineView.swift`:

```swift
import SwiftUI

struct TimelineView: View {
    @Environment(SampleReportStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("타임라인")
                    .font(.largeTitle.bold())

                ForEach(store.timelineSessions) { session in
                    HStack(alignment: .top, spacing: 14) {
                        Circle()
                            .fill(session.category.color)
                            .frame(width: 10, height: 10)
                            .padding(.top, 8)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(session.name).font(.headline)
                                Spacer()
                                Text(DurationFormatting.compact(seconds: session.durationSeconds))
                                    .font(.headline)
                            }
                            Text(session.title ?? session.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(session.category.koreanLabel)
                                .font(.caption)
                                .foregroundStyle(session.category.color)
                        }
                        .padding()
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    }
                }
            }
            .padding(28)
        }
    }
}
```

- [ ] **Step 5: Add remaining placeholder screens**

Create `macos-native/Sources/FlowPilotNative/UI/WeeklyReportView.swift`:

```swift
import SwiftUI

struct WeeklyReportView: View {
    var body: some View {
        ContentUnavailableView("주간 리포트", systemImage: "chart.bar", description: Text("네이티브 주간 리포트는 다음 단계에서 기존 데이터와 연결합니다."))
    }
}
```

Create `macos-native/Sources/FlowPilotNative/UI/ReviewView.swift`:

```swift
import SwiftUI

struct ReviewView: View {
    var body: some View {
        ContentUnavailableView("미분류 검토", systemImage: "tray", description: Text("미분류 항목 분류는 데이터 연결 단계에서 활성화합니다."))
    }
}
```

Create `macos-native/Sources/FlowPilotNative/UI/RulesView.swift`:

```swift
import SwiftUI

struct RulesView: View {
    var body: some View {
        ContentUnavailableView("분류 규칙", systemImage: "slider.horizontal.3", description: Text("규칙 관리는 기존 규칙 저장소 이식 후 연결합니다."))
    }
}
```

- [ ] **Step 6: Verify native package builds**

Run:

```bash
cd macos-native
swift build
swift test
```

Expected: build succeeds and tests pass.

### Task 5: Repository Verification

**Files:**
- No source edits unless verification exposes a compile error.

- [ ] **Step 1: Verify existing frontend tests**

Run:

```bash
npm test
```

Expected: existing frontend/script tests pass.

- [ ] **Step 2: Verify existing Rust tests**

Run:

```bash
cargo test --manifest-path src-tauri/Cargo.toml
```

Expected: existing Rust tests pass.

- [ ] **Step 3: Verify native Swift tests**

Run:

```bash
cd macos-native
swift test
```

Expected: native Swift tests pass.

## Self-Review

- Spec coverage: This plan covers the first milestone from the SwiftUI native design: separate native app, native shell, mirrored data concepts, menu bar item, and tests.
- Known deferred scope: collector migration, SQLite migration, browser bridge reuse, `.app` packaging, signing, notarization, and replacing the installed Tauri app are intentionally outside milestone 1.
- Placeholder scan: Placeholder views are explicit milestone placeholders with user-facing Korean copy and are limited to screens that cannot be real until data migration starts.
