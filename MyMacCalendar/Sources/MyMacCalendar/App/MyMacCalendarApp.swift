import SwiftUI
import SwiftData
import MyMacCalendarCore

enum CalendarApplicationState {
    case ready(ModelContainer)
    case failed
}

@MainActor
final class AppStartupGate {
    static let shared = AppStartupGate()
    private(set) var isStoreReady = false

    func setStoreReady(_ isReady: Bool) {
        isStoreReady = isReady
    }
}

@main
struct MyMacCalendarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let applicationState: CalendarApplicationState

    init() {
        do {
            let container = try CalendarStore.makeContainer()
            applicationState = .ready(container)
            AppStartupGate.shared.setStoreReady(true)
        } catch {
            applicationState = .failed
            AppStartupGate.shared.setStoreReady(false)
            NSLog("Calendar store unavailable (%@)", String(reflecting: type(of: error)))
        }
    }

    var body: some Scene {
        WindowGroup(AppVersion.name) {
            switch applicationState {
            case .ready(let container):
                MainWindowView()
                    .modelContainer(container)
            case .failed:
                StorageFailureView()
            }
        }
        .defaultSize(width: 1240, height: 720)
        .commands {
            CommandGroup(after: .pasteboard) {
                Button("일정 검색") {
                    NotificationCenter.default.post(name: .focusCalendarSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }

        Settings {
            switch applicationState {
            case .ready(let container):
                SettingsView()
                    .modelContainer(container)
            case .failed:
                StorageFailureView()
            }
        }
    }
}
