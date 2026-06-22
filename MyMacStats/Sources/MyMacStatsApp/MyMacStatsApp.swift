import SwiftUI

@main
struct MyMacStatsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1120, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
