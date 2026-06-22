import SwiftUI
import MyMacStatsAppSupport
import MyMacStatsCore

struct ContentView: View {
    @StateObject private var viewModel = DashboardViewModel()
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
        .task {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}
