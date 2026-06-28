import Foundation

public enum BrowserSessionEnricher {
    private static let matchedTitleMaxAgeSeconds: TimeInterval = 12 * 60 * 60
    private static let recentFallbackMaxAgeSeconds: TimeInterval = 30

    public static func enrich(
        session: ActivitySessionRecord,
        events: [BrowserEventRecord]
    ) -> ActivitySessionRecord {
        guard session.domain == nil,
              !session.isIdle,
              isChromiumBrowserSession(session),
              let event = chooseEvent(for: session, events: events) else {
            return session
        }

        return ActivitySessionRecord(
            id: session.id,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            durationSeconds: session.durationSeconds,
            appName: session.appName,
            processName: session.processName,
            windowTitle: session.windowTitle,
            domain: event.domain,
            url: nil,
            isIdle: session.isIdle
        )
    }

    private static func chooseEvent(
        for session: ActivitySessionRecord,
        events: [BrowserEventRecord]
    ) -> BrowserEventRecord? {
        events.first { event in
            ageSeconds(event, relativeTo: session.endedAt)
                .map { $0 >= 0 && $0 <= matchedTitleMaxAgeSeconds }
                .unwrap(false)
                && browserTitleMatches(windowTitle: session.windowTitle, tabTitle: event.title)
        } ?? events.first { event in
            ageSeconds(event, relativeTo: session.endedAt)
                .map { $0 >= 0 && $0 <= recentFallbackMaxAgeSeconds }
                .unwrap(false)
        }
    }

    private static func ageSeconds(_ event: BrowserEventRecord, relativeTo observedAt: Date) -> TimeInterval? {
        observedAt.timeIntervalSince(event.occurredAt)
    }

    private static func browserTitleMatches(windowTitle: String, tabTitle: String) -> Bool {
        let windowTitle = normalizeBrowserTitle(windowTitle)
        let tabTitle = normalizeBrowserTitle(tabTitle)

        return !tabTitle.isEmpty
            && (windowTitle.contains(tabTitle) || tabTitle.contains(windowTitle))
    }

    private static func normalizeBrowserTitle(_ title: String) -> String {
        title
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func isChromiumBrowserSession(_ session: ActivitySessionRecord) -> Bool {
        let identity = "\(session.appName) \(session.processName)".lowercased()
        return [
            "google chrome",
            "chrome.exe",
            "microsoft edge",
            "msedge",
            "brave browser",
            "brave.exe",
            "arc",
            "chromium"
        ].contains { identity.contains($0) }
    }
}

private extension Optional where Wrapped == Bool {
    func unwrap(_ fallback: Bool) -> Bool {
        self ?? fallback
    }
}
