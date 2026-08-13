# Metric Refresh Reliability Design

## Goal

Reduce MyMacStats' own resource use and prevent short sampler failures from making the dashboard flicker or lose useful data, while preserving fresh process identity checks before termination.

## Scope

This change covers scheduled sampling, per-metric cadence, last-known-good values, failure transitions, and forced process refresh for termination validation.

RAM notification controls and authorization status remain a separate follow-up. They do not share the sampling lifecycle and will be designed independently after this work is verified.

## Current Behavior

`DashboardViewModel` owns one refresh task. Every loop calls `SystemMetricsService.refresh()`, which samples CPU, memory, disk, network, battery, and processes sequentially.

This means a one-second refresh setting also runs `/bin/ps`, disk capacity, disk I/O, and battery APIs every second. A nil result immediately removes most metric values. Process sampling converts command failure to an empty list, so the service cannot distinguish an actual empty list from a failed command.

## Selected Approach

Keep one refresh loop and move cadence decisions into `SystemMetricsService`.

This retains a single owner for sampler state and avoids independent timers racing to mutate the same snapshot. The service will cache each metric independently, decide whether it is due at the requested time, and return a complete snapshot assembled from fresh or retained values.

Separate timers per metric were rejected because they add cancellation, actor-isolation, and snapshot-coordination complexity. Running all samplers concurrently was rejected because it does not reduce unnecessary sampling frequency and the CPU and network samplers contain mutable delta state.

## Sampling Cadence

The dashboard's selected refresh interval remains the base interval for the refresh loop.

| Metric | Effective cadence |
|---|---|
| CPU | Selected refresh interval |
| Memory | Selected refresh interval |
| Network | Selected refresh interval |
| Processes | `max(selected interval, 2 seconds)` |
| Disk | `max(selected interval, 10 seconds)` |
| Battery | `max(selected interval, 10 seconds)` |
| Disk-space candidates | Existing 60-second background interval |

When the selected interval changes, the next loop uses the new value. A metric already overdue under the new cadence is sampled immediately.

## Refresh Reasons

The service will distinguish two refresh reasons:

- `scheduled(baseInterval:)`: applies normal cadence and cache rules.
- `terminationValidation`: forces a new process sample before validating PID, name, path, and bundle identity. Other metrics keep their normal cadence.

The first scheduled refresh has no cached timestamps, so every metric is due immediately.

`DashboardViewModel.confirmPendingTermination` must use `terminationValidation`. A cached process list is never sufficient for a destructive action.

## Cached Sample State

The service stores the following for CPU, memory, disk, network, battery, and processes:

- Last successful value.
- Time of the last successful sample.
- Time of the last attempted sample.
- Number of consecutive failed due attempts.
- Last summary produced from a successful sample.

Skipping a sample because it is not due does not increment the failure count and does not mark the value stale.

A successful due sample replaces the cached value and resets the failure count.

## Failure Policy

For CPU, memory, disk, network, and battery:

1. If no successful value has ever been recorded, a failed due sample produces `unavailable`.
2. On the first failure after a successful sample, retain the last value, preserve its last-success timestamp, and mark the summary as stale.
3. On the second consecutive failed due sample, stop presenting the cached value and produce `unavailable`.
4. A later success restores a fresh value and resets the failure count.

The stale summary uses `warning` unless the retained metric's evaluated health is already `critical`. Its detail text includes `Using last sample` so the warning is not mistaken for a current reading.

Network follows the same cache policy. This replaces the current special case where the first nil sample shows only `Unavailable` text with warning health.

For processes:

1. Process sampling returns an optional list. `nil` means the command failed; an empty array is a valid successful result.
2. The first failure retains the last successful list.
3. The second consecutive failure replaces it with an empty list and marks the Processes summary unavailable.
4. Termination validation fails closed when its forced process sample returns `nil`; it must not validate against cached process data or send a signal.

## Snapshot Semantics

`SystemMetricsSnapshot.updatedAt` remains the time the snapshot was assembled.

Each `MetricSummary.updatedAt` represents the last successful sample time for that metric. This allows stale data to retain an accurate age instead of appearing newly measured.

Health evaluation and health debounce advance only when a due sampler returns a new value. A cadence skip or retained stale value must not count as another health sample. A skipped metric reuses its last successful summary unchanged; a stale metric derives its warning from that summary without advancing `HealthEvaluator`.

The Processes summary health can now be `warning` or `unavailable` when process sampling is stale or unavailable. Normal successful sampling remains `normal`.

CPU history appends only fresh CPU samples. Cached values are not duplicated in the graph.

Memory swap-increase evaluation runs only on fresh memory samples. Reusing a cached memory snapshot cannot create a false swap-growth critical state.

## Public Interfaces

`SystemSampler.sampleProcesses()` changes from `[ProcessMetric]` to `[ProcessMetric]?`.

`SystemMetricsService.refresh` accepts a refresh reason. The scheduled reason includes the selected base interval. The default remains a one-second scheduled refresh for compatibility with direct callers.

`DashboardViewModel.refreshNow()` passes its current selected interval. Termination confirmation requests a termination-validation refresh and handles a failed forced process sample as a non-destructive validation failure.

## Error Handling

Sampler errors remain isolated to their metric. One failed API must not fail the full refresh or stop the loop.

Cancellation must not be converted into a sampler failure. The refresh loop exits after cancellation and does not publish a partially assembled snapshot from a cancelled operation.

Disk-space candidate scanning remains independent and retains its current timeout and fallback behavior.

## Test Strategy

Tests use deterministic timestamps and a recording sampler.

Required behavior tests:

- First refresh samples every metric.
- One-second scheduled refresh does not resample processes before two seconds.
- One-second scheduled refresh does not resample disk or battery before ten seconds.
- Changing to a slower base interval changes future due times without discarding cached values.
- Skipped samples do not increase failure counters.
- Skipped disk and battery samples do not advance health debounce.
- First due failure retains the last CPU value and exposes a stale warning with the original timestamp.
- Second due failure makes the CPU summary unavailable.
- A success after failures restores fresh state.
- Cached CPU values are not appended to history.
- Cached memory values do not trigger swap-increase health evaluation.
- Process failure is distinct from a successful empty process list.
- First process failure retains the list; second failure clears it and marks Processes unavailable.
- Termination validation always forces process sampling even when the normal process cadence has not elapsed.
- Failed forced process sampling blocks termination and sends no signal.

Existing health, process termination, sorting, grouping, packaging, and lifecycle tests must continue to pass.

## Documentation And Verification

Update the README and feature verification checklist to describe the effective cadence and stale-value policy.

Completion requires:

- Full XCTest suite passes.
- Release build succeeds.
- App bundle and personal distribution checks succeed.
- The built app launches and displays populated metrics.
- Runtime observation confirms process sampling is not performed every one-second UI tick.
- No new privacy permission prompt appears during the smoke run.
