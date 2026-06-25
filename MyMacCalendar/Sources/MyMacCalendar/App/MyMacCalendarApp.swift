import SwiftUI
import SwiftData
import MyMacCalendarCore

@main
struct MyMacCalendarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer

    init() {
        do {
            container = try CalendarStore.makeContainer()
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup(AppVersion.name) {
            MainWindowView()
                .modelContainer(container)
        }
        .defaultSize(width: 1100, height: 720)

        Settings {
            SettingsView()
                .modelContainer(container)
        }
    }
}
