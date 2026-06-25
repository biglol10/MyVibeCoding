import Foundation
import SwiftData

@Model
public final class AppSettings {
    @Attribute(.unique) public var id: String
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

    public init(
        id: String = "default",
        launchAtLogin: Bool = false,
        showMenuBar: Bool = true,
        floatingWidgetEnabled: Bool = true,
        floatingWidgetAlwaysOnTop: Bool = true,
        floatingWidgetOpacity: Double = 0.96,
        floatingWidgetVisibleCount: Int = 5,
        defaultReminderHour: Int = 9,
        defaultReminderMinute: Int = 0,
        theme: String = "system",
        calendarDensity: String = "comfortable"
    ) {
        self.id = id
        self.launchAtLogin = launchAtLogin
        self.showMenuBar = showMenuBar
        self.floatingWidgetEnabled = floatingWidgetEnabled
        self.floatingWidgetAlwaysOnTop = floatingWidgetAlwaysOnTop
        self.floatingWidgetOpacity = floatingWidgetOpacity
        self.floatingWidgetVisibleCount = floatingWidgetVisibleCount
        self.defaultReminderHour = defaultReminderHour
        self.defaultReminderMinute = defaultReminderMinute
        self.theme = theme
        self.calendarDensity = calendarDensity
    }
}
