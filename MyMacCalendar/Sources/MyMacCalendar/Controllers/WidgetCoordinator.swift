import SwiftUI
import MyMacCalendarCore

@MainActor
final class WidgetCoordinator {
    static let shared = WidgetCoordinator()

    private let controller = FloatingWidgetController()
    private var manualVisibilityOverride: Bool?
    private var currentEvents: [CalendarEvent] = []
    private var currentSettings = WidgetSettingsSnapshot()

    private init() {}

    func update(events: [CalendarEvent], settings: AppSettings?) {
        currentEvents = events
        currentSettings = WidgetSettingsSnapshot(settings: settings)
        render()
    }

    func toggleVisibility() {
        let currentlyVisible = manualVisibilityOverride ?? currentSettings.isEnabled
        manualVisibilityOverride = !currentlyVisible
        render()
    }

    private func render() {
        let shouldShow = manualVisibilityOverride ?? currentSettings.isEnabled
        guard shouldShow else {
            controller.hide()
            return
        }

        let occurrences = EventService().upcomingOccurrences(
            from: Date(),
            events: currentEvents,
            limit: currentSettings.visibleCount
        )
        controller.show(
            occurrences: occurrences,
            opacity: currentSettings.opacity,
            alwaysOnTop: currentSettings.alwaysOnTop,
            onSelect: { [weak self] occurrence in
                guard let self,
                      let event = self.currentEvents.first(where: { $0.id == occurrence.eventID }) else {
                    return
                }
                self.controller.showDetail(for: event)
            }
        )
    }
}

private struct WidgetSettingsSnapshot {
    var isEnabled = true
    var alwaysOnTop = true
    var opacity = 0.96
    var visibleCount = 5

    init(settings: AppSettings? = nil) {
        guard let settings else { return }
        isEnabled = settings.floatingWidgetEnabled
        alwaysOnTop = settings.floatingWidgetAlwaysOnTop
        opacity = settings.floatingWidgetOpacity
        visibleCount = settings.floatingWidgetVisibleCount
    }
}
