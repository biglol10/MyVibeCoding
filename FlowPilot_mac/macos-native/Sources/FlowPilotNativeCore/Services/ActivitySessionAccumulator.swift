import Foundation

public final class ActivitySessionAccumulator {
    public typealias IDProvider = () -> String

    private struct OpenSession {
        let id: String
        let startedAt: Date
        var sample: ActivitySample
    }

    private var openSession: OpenSession?
    private let idProvider: IDProvider

    public init(idProvider: @escaping IDProvider = { "active-window:\(UUID().uuidString)" }) {
        self.idProvider = idProvider
    }

    public func observe(_ sample: ActivitySample) -> [ActivitySessionRecord] {
        guard var openSession else {
            let next = OpenSession(id: idProvider(), startedAt: sample.observedAt, sample: sample)
            self.openSession = next
            return [record(from: next, endedAt: sample.observedAt)]
        }

        if shouldMerge(openSession.sample, sample) {
            openSession.sample = mergedSample(current: openSession.sample, next: sample)
            self.openSession = openSession
            return [record(from: openSession, endedAt: sample.observedAt)]
        }

        let closed = record(from: openSession, endedAt: sample.observedAt)
        let next = OpenSession(id: idProvider(), startedAt: sample.observedAt, sample: sample)
        self.openSession = next
        return [closed, record(from: next, endedAt: sample.observedAt)]
    }

    private func record(from openSession: OpenSession, endedAt: Date) -> ActivitySessionRecord {
        let endedAt = max(endedAt, openSession.startedAt)
        let duration = max(1, Int(endedAt.timeIntervalSince(openSession.startedAt)))

        return ActivitySessionRecord(
            id: openSession.id,
            startedAt: openSession.startedAt,
            endedAt: endedAt,
            durationSeconds: duration,
            appName: openSession.sample.appName,
            processName: openSession.sample.processName,
            windowTitle: openSession.sample.windowTitle,
            domain: openSession.sample.domain,
            url: nil,
            isIdle: openSession.sample.isIdle
        )
    }

    private func shouldMerge(_ current: ActivitySample, _ next: ActivitySample) -> Bool {
        guard current.appName == next.appName,
              current.processName == next.processName,
              current.domain == next.domain,
              current.isIdle == next.isIdle else {
            return false
        }

        return normalizedTitle(current.windowTitle) == normalizedTitle(next.windowTitle)
            || isGenericFallbackTitle(current.windowTitle, sample: current)
            || isGenericFallbackTitle(next.windowTitle, sample: next)
    }

    private func mergedSample(current: ActivitySample, next: ActivitySample) -> ActivitySample {
        ActivitySample(
            observedAt: next.observedAt,
            appName: next.appName,
            processName: next.processName,
            windowTitle: preferredTitle(current: current, next: next),
            domain: next.domain,
            isIdle: next.isIdle
        )
    }

    private func preferredTitle(current: ActivitySample, next: ActivitySample) -> String {
        if isGenericFallbackTitle(next.windowTitle, sample: next),
           !isGenericFallbackTitle(current.windowTitle, sample: current) {
            return current.windowTitle
        }
        return next.windowTitle
    }

    private func isGenericFallbackTitle(_ title: String, sample: ActivitySample) -> Bool {
        let normalized = normalizedTitle(title)
        return normalized == normalizedTitle(sample.appName)
            || normalized == normalizedTitle(sample.processName)
    }

    private func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
