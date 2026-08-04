import Foundation

public struct AppSettingsSnapshot: Equatable, Sendable {
    public var launchAtLogin: Bool
    public var showMenuBar: Bool
    public var floatingWidgetEnabled: Bool
    public var floatingWidgetAlwaysOnTop: Bool
    public var floatingWidgetOpacity: Double
    public var floatingWidgetVisibleCount: Int
    public var defaultReminderHour: Int
    public var defaultReminderMinute: Int
    public var theme: String
    public var calendarDensity: String
}

public enum SettingsValidation {
    public static let defaultOpacity = 0.96
    public static let opacityRange = 0.4...1.0
    public static let visibleCountRange = 3...12
    public static let supportedThemes = Set(["system", "light", "dark"])
    public static let supportedDensities = Set(["comfortable", "compact"])

    public static func visibleCount(_ value: Int) -> Int {
        min(max(value, visibleCountRange.lowerBound), visibleCountRange.upperBound)
    }

    public static func opacity(_ value: Double) -> Double {
        guard value.isFinite else { return defaultOpacity }
        return min(max(value, opacityRange.lowerBound), opacityRange.upperBound)
    }

    public static func opacityPercent(_ value: Double) -> Int {
        Int((opacity(value) * 100).rounded())
    }

    public static func reminderHour(_ value: Int) -> Int {
        min(max(value, 0), 23)
    }

    public static func reminderMinute(_ value: Int) -> Int {
        min(max(value, 0), 59)
    }

    public static func theme(_ value: String) -> String {
        supportedThemes.contains(value) ? value : "system"
    }

    public static func density(_ value: String) -> String {
        supportedDensities.contains(value) ? value : "comfortable"
    }

    public static func snapshot(_ settings: AppSettings?) -> AppSettingsSnapshot {
        guard let settings else { return snapshot(AppSettings()) }
        return AppSettingsSnapshot(
            launchAtLogin: settings.launchAtLogin,
            showMenuBar: settings.showMenuBar,
            floatingWidgetEnabled: settings.floatingWidgetEnabled,
            floatingWidgetAlwaysOnTop: settings.floatingWidgetAlwaysOnTop,
            floatingWidgetOpacity: opacity(settings.floatingWidgetOpacity),
            floatingWidgetVisibleCount: visibleCount(settings.floatingWidgetVisibleCount),
            defaultReminderHour: reminderHour(settings.defaultReminderHour),
            defaultReminderMinute: reminderMinute(settings.defaultReminderMinute),
            theme: theme(settings.theme),
            calendarDensity: density(settings.calendarDensity)
        )
    }

    @discardableResult
    public static func repair(_ settings: AppSettings) -> Bool {
        let normalized = snapshot(settings)
        var changed = false

        changed = assign(normalized.floatingWidgetOpacity, to: &settings.floatingWidgetOpacity) || changed
        changed = assign(normalized.floatingWidgetVisibleCount, to: &settings.floatingWidgetVisibleCount) || changed
        changed = assign(normalized.defaultReminderHour, to: &settings.defaultReminderHour) || changed
        changed = assign(normalized.defaultReminderMinute, to: &settings.defaultReminderMinute) || changed
        changed = assign(normalized.theme, to: &settings.theme) || changed
        changed = assign(normalized.calendarDensity, to: &settings.calendarDensity) || changed
        return changed
    }

    private static func assign<T: Equatable>(_ value: T, to target: inout T) -> Bool {
        guard target != value else { return false }
        target = value
        return true
    }
}
