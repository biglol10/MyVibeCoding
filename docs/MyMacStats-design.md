# MyMacStats Design Brief

## 1. Product Summary

`MyMacStats` is a macOS system monitoring app inspired by Stats, but focused on a dashboard workflow rather than only menu bar numbers. The app shows high-level system health in a left sidebar and shows the cause, ranking, or detailed list for the selected metric in the main area.

The core experience is: if a metric becomes unhealthy, the user can immediately see what is causing it. For example, when RAM is nearly full, the RAM item in the sidebar changes color, and selecting it shows the apps/processes using the most memory.

## 2. Product Goals

- Show macOS system status in one compact dashboard.
- Refresh CPU, RAM, disk, network, battery, and process data on a schedule.
- Use color to make warning and critical states visible.
- Let the user click each metric to inspect the relevant list or root cause.
- Keep a dense, utility-focused macOS UI similar to `MyMacClean`.
- Provide a clear MVP that can later grow into a menu bar app.

## 3. Non-Goals For MVP

The first version should not include these features:

- Fan speed and temperature sensors.
- GPU sensor details.
- Notification Center widgets.
- iCloud sync.
- Historical daily reports.
- Killing processes.
- MyMacClean or FlowPilot integration.

Temperature, fan, and GPU sensor support can be added later because they often require lower-level APIs or SMC access.

## 4. App Shape

The recommended final shape is a menu bar app with a dashboard window.

MVP can start as a normal SwiftUI macOS window app. After the core monitoring dashboard works, convert it into a menu bar resident app.

Final behavior:

- The menu bar item shows one selected metric, such as `CPU 34%` or `RAM 13.8G`.
- Clicking the menu bar item opens the dashboard window.
- The dashboard window uses a three-column utility layout.
- A future setting can hide the Dock icon.

## 5. UI Layout

The UI should follow the visual structure shown in the MyMacClean screenshot:

- Left sidebar: system metric categories and live summaries.
- Middle panel: ranked list or metric-specific rows.
- Right detail panel: selected item details.

### Left Sidebar Items

- CPU
- RAM
- Disk
- Network
- Battery
- Processes
- Settings

### Sidebar Row Examples

```text
CPU        34%
RAM        13.8 / 16 GB
Disk       82%
Network    ↓ 4.2 MB/s  ↑ 850 KB/s
Battery    78%
Processes  412
```

Each row should show:

- Icon
- Metric title
- Current value
- Optional secondary text
- Health state color

## 6. Health States

Every metric summary can be in one of four states:

- `normal`: default text color.
- `warning`: yellow text or yellow status dot.
- `critical`: red text or red status dot.
- `unavailable`: gray text when data cannot be read.

Color changes must not flicker because of one-off spikes. Use debounce rules: a new health state should be applied only when the same state is observed for at least two consecutive samples.

## 7. Health Rules

### CPU

- Warning: total CPU usage is at least 70% for 10 seconds.
- Critical: total CPU usage is at least 90% for 10 seconds.

### RAM

- Warning: memory usage is at least 80% or macOS memory pressure is warning.
- Critical: memory usage is at least 90%, memory pressure is critical, or swap usage keeps increasing.

### Disk

- Warning: free space is below 20%.
- Critical: free space is below 10%.

### Network

Network throughput is not unhealthy by itself. High upload/download speed should be shown as activity, not warning.

Network becomes warning or critical only when:

- No active interface can be found.
- The network sampler repeatedly fails.
- The selected interface is disconnected.

### Battery

- Warning: battery is below 20%.
- Critical: battery is below 10% or macOS reports service recommended.

## 8. Refresh Policy

Default refresh intervals:

- CPU: 1 second.
- RAM: 1 second.
- Network: 1 second.
- Process list: 2 seconds.
- Disk capacity: 10 seconds.
- Battery: 10 seconds.

Settings should eventually allow these intervals:

- 1 second
- 2 seconds
- 5 seconds
- 10 seconds

The app should avoid doing heavy work every second. Disk and battery do not need to refresh as often as CPU and memory.

## 9. Metric Screens

### CPU Screen

The CPU screen should show:

- Total CPU usage.
- User/system/idle split if available.
- Top CPU-consuming processes.
- Recent 60-second sparkline chart.

Middle list:

- Process name
- PID
- CPU %
- Memory usage

Right detail:

- Process name
- PID
- CPU %
- Memory
- Executable path if available
- Bundle identifier if available

### RAM Screen

The RAM screen should show:

- Used memory.
- Free memory.
- Compressed memory.
- Cached memory if available.
- Swap used.
- Memory pressure state.
- Top memory-consuming processes.

If RAM is warning or critical, the top of the detail area should summarize the likely cause, such as "Chrome and Xcode are using most memory."

### Disk Screen

The Disk screen should show:

- Volumes.
- Total capacity.
- Used space.
- Free space.
- Free percentage.
- Read/write throughput if available.

MVP should support the main system volume first. Additional mounted volumes can be added after the core UI works.

### Network Screen

The Network screen should show:

- Active interface.
- Download speed.
- Upload speed.
- Cumulative received bytes.
- Cumulative sent bytes.
- Connection status.

The first implementation can show aggregate active interface data. Per-process network usage is not required in MVP.

### Battery Screen

The Battery screen should show:

- Battery percentage.
- Charging state.
- Power source.
- Time remaining if available.
- Cycle count if available.
- Service warning if available.

If some values are unavailable on a desktop Mac, the UI should show a calm unavailable state instead of failing.

### Processes Screen

The Processes screen should show a full process list with:

- Process name
- PID
- CPU %
- Memory usage
- Optional app path

Required interactions:

- Search by process name.
- Sort by CPU.
- Sort by memory.
- Sort by name.
- Sort by PID.

Process termination is not part of MVP.

## 10. Data Model

Recommended Swift models:

```swift
enum MetricKind: CaseIterable, Identifiable {
    case cpu
    case memory
    case disk
    case network
    case battery
    case processes

    var id: Self { self }
}

enum HealthState: Equatable {
    case normal
    case warning
    case critical
    case unavailable
}

struct MetricSummary: Equatable, Identifiable {
    let kind: MetricKind
    let title: String
    let valueText: String
    let detailText: String?
    let health: HealthState
    let updatedAt: Date

    var id: MetricKind { kind }
}

struct ProcessMetric: Equatable, Identifiable {
    let pid: Int32
    let name: String
    let cpuPercent: Double
    let memoryBytes: UInt64
    let path: String?
    let bundleIdentifier: String?

    var id: Int32 { pid }
}
```

Additional metric-specific structs can be added:

```swift
struct MemorySnapshot: Equatable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let freeBytes: UInt64
    let compressedBytes: UInt64?
    let swapUsedBytes: UInt64?
    let pressure: MemoryPressure
}

enum MemoryPressure: Equatable {
    case normal
    case warning
    case critical
    case unavailable
}
```

## 11. Architecture

Recommended modules:

- `MyMacStatsApp`: app entry point.
- `MenuBarController`: menu bar item and dashboard window control.
- `SystemMetricsService`: owns refresh timers and publishes current metrics.
- `CPUSampler`: reads CPU usage.
- `MemorySampler`: reads memory usage and pressure.
- `DiskSampler`: reads disk usage.
- `NetworkSampler`: reads network throughput.
- `BatterySampler`: reads battery and power source information.
- `ProcessSampler`: reads process CPU and memory data.
- `MetricsStore`: keeps latest snapshots and short history.
- `HealthEvaluator`: converts raw snapshots into `HealthState`.
- `DashboardViewModel`: adapts service data for SwiftUI.
- `SidebarView`: left metric list.
- `MetricListView`: middle list panel.
- `MetricDetailView`: right detail panel.
- `SettingsView`: refresh interval and display preferences.

The samplers should be isolated from SwiftUI. The UI should depend on view models, not directly on system calls.

## 12. Data Flow

1. `SystemMetricsService` starts refresh loops.
2. Each sampler reads raw system data at its configured interval.
3. `MetricsStore` stores the latest snapshot and recent history.
4. `HealthEvaluator` computes health states with debounce.
5. `DashboardViewModel` publishes summaries and selected screen data.
6. SwiftUI views render sidebar, list, and details.

The selected metric should not control whether data is collected. Core metrics should continue refreshing even when not selected so sidebar status stays current.

## 13. Error Handling

The app should degrade gracefully:

- If a sampler fails once, keep the last known value and mark data as stale internally.
- If a sampler fails repeatedly, set its health state to `unavailable`.
- If a process disappears during sampling, ignore it in the next process list.
- If a field cannot be read, show `Unavailable` for that field only.
- If permissions are needed, explain the required macOS setting in the relevant screen.

The app must not crash because one metric source failed.

## 14. Settings

MVP settings:

- Refresh interval preset.
- Menu bar metric selection.
- Show/hide Dock icon can be a later setting.
- Warning thresholds can be fixed in MVP and configurable later.

Future settings:

- CPU warning/critical thresholds.
- RAM warning/critical thresholds.
- Disk free-space warning thresholds.
- Menu bar text format.
- Launch at login.

## 15. Visual Direction

Use a dark, native macOS utility style similar to MyMacClean.

Design rules:

- Dense but readable layout.
- No marketing hero UI.
- No decorative cards inside cards.
- Use a sidebar for navigation.
- Use tables/lists for process ranking.
- Use subtle dividers.
- Use small status dots or colored text for health states.
- Use compact sparklines, not large chart-heavy dashboards.

Warning colors should be informative, not loud:

- Warning: yellow/orange accent.
- Critical: red accent.
- Unavailable: muted gray.

## 16. MVP Completion Criteria

MVP is complete when:

- App launches as a macOS SwiftUI app.
- Dashboard has left sidebar, middle list panel, and right detail panel.
- Sidebar shows CPU, RAM, Disk, Network, Battery, and Processes.
- Sidebar values refresh automatically.
- CPU and RAM health colors change based on thresholds.
- CPU screen shows top CPU processes.
- RAM screen shows top memory processes.
- Disk screen shows at least the main volume usage.
- Network screen shows active interface upload/download speed.
- Battery screen shows available power status.
- Process screen supports search and sorting.
- Health evaluation logic has unit tests.
- Formatting helpers have unit tests.
- README explains environment, run, test, and build commands.

## 17. Suggested Implementation Phases

### Phase 1: Project Skeleton

- Create `MyMacStats` Swift package or macOS app project.
- Add SwiftUI dashboard shell.
- Add mock metric data.
- Implement sidebar/list/detail layout.

### Phase 2: Health And Formatting

- Add `MetricKind`, `HealthState`, `MetricSummary`, and formatting helpers.
- Add `HealthEvaluator` with threshold and debounce behavior.
- Add unit tests for health evaluation.

### Phase 3: Real CPU And RAM

- Implement `CPUSampler`.
- Implement `MemorySampler`.
- Implement `ProcessSampler` for CPU and memory ranking.
- Connect CPU and RAM screens to real data.

### Phase 4: Disk, Network, Battery

- Implement `DiskSampler`.
- Implement `NetworkSampler`.
- Implement `BatterySampler`.
- Add unavailable-state handling.

### Phase 5: Menu Bar Mode

- Add menu bar item.
- Open dashboard window from menu bar.
- Show selected metric in menu bar.

### Phase 6: Packaging

- Add build script.
- Add local ad-hoc signing.
- Add README.
- Add downloadable zip output.

## 18. Testing Plan

Unit tests:

- `HealthEvaluator` threshold behavior.
- Debounce behavior.
- Byte formatting.
- Percent formatting.
- Process sorting.
- Stale/unavailable state transitions.

Integration-style tests:

- `SystemMetricsService` can merge sampler outputs into summaries.
- View model updates selected metric correctly.
- Mock samplers can simulate warning and critical states.

Manual QA:

- Run app for 10 minutes and confirm refresh remains stable.
- Open CPU-heavy app and confirm CPU list changes.
- Open memory-heavy app and confirm RAM list changes.
- Disconnect network and confirm network unavailable state.
- Run on battery and power adapter if possible.

## 19. Future Extensions

- MyMacClean integration: disk warning screen can offer to open MyMacClean.
- FlowPilot integration: compare high-resource apps with productivity sessions.
- Notifications for sustained critical CPU/RAM/disk states.
- Process termination with confirmation.
- Launch at login.
- Temperature and fan sensors.
- Per-process network usage.
- Historical charts and daily summaries.

## 20. Recommended Name

Primary name:

- `MyMacStats`

Alternatives:

- `MacVitals`
- `SystemPanel`
- `MySystemWatch`
- `MacPulse`

`MyMacStats` is recommended because it fits the existing repository naming style with `MyMacClean` and clearly communicates the app purpose.

