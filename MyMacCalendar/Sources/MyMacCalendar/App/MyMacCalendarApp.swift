import SwiftUI
import SwiftData
import MyMacCalendarCore

@main
struct MyMacCalendarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container: ModelContainer

    init() {
        container = Self.makeModelContainer()
    }

    private static func makeModelContainer() -> ModelContainer {
        do {
            return try CalendarStore.makeContainer()
        } catch {
            NSLog("Failed to create SwiftData container: \(error). Falling back to in-memory store.")
            do {
                return try CalendarStore.makeInMemoryContainer()
            } catch {
                preconditionFailure("Unable to create any SwiftData container: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup(AppVersion.name) {
            MainWindowView()
                .modelContainer(container)
        }
        .defaultSize(width: 1240, height: 720)

        Settings {
            SettingsView()
                .modelContainer(container)
        }
    }
}
