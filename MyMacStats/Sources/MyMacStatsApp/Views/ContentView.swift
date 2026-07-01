import SwiftUI
import MyMacStatsAppSupport
import MyMacStatsCore

struct ContentView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var isSettingsSelected = false

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel, isSettingsSelected: $isSettingsSelected)
        } content: {
            MetricListView(viewModel: viewModel, isSettingsSelected: $isSettingsSelected)
        } detail: {
            MetricDetailView(viewModel: viewModel, isSettingsSelected: isSettingsSelected)
        }
        .preferredColorScheme(.dark)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(terminationAlertTitle, isPresented: terminationAlertBinding) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelPendingTermination()
            }
            Button(viewModel.pendingTerminationMode == .forceQuit ? "Force Quit" : "Quit", role: .destructive) {
                viewModel.confirmPendingTermination()
            }
        } message: {
            if let displayName = viewModel.pendingTerminationDisplayName {
                Text(
                    [
                        displayName,
                        viewModel.pendingTerminationDetailText
                    ]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                )
            }
        }
        .task {
            viewModel.start()
        }
    }

    private var terminationAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingTerminationProcess != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.cancelPendingTermination()
                }
            }
        )
    }

    private var terminationAlertTitle: String {
        let target = viewModel.pendingTerminationTargetsApp ? "App" : "Process"
        return viewModel.pendingTerminationMode == .forceQuit ? "Force Quit \(target)?" : "Quit \(target)?"
    }
}
