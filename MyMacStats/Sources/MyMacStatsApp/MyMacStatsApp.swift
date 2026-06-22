import SwiftUI
import MyMacStatsAppSupport

@main
struct MyMacStatsApp: App {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 1120, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarPopoverView(viewModel: viewModel)
        } label: {
            Text(menuBarTitle)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarTitle: String {
        let cpu = viewModel.snapshot.summary(for: .cpu)?.valueText ?? "--"
        let memory = viewModel.snapshot.summary(for: .memory)?.valueText ?? "--"
        return "CPU \(cpu) RAM \(memory)"
    }
}
