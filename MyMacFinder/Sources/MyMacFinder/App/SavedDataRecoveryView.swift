import SwiftUI

enum SavedDataRecoveryArea: String, Identifiable, Equatable {
    case settings
    case sidebar
    case session

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings: return "General Settings"
        case .sidebar: return "Sidebar"
        case .session: return "Previous Session"
        }
    }

    var systemImage: String {
        switch self {
        case .settings: return "slider.horizontal.3"
        case .sidebar: return "sidebar.left"
        case .session: return "rectangle.stack"
        }
    }
}

struct SavedDataRecoveryItem: Identifiable, Equatable {
    let area: SavedDataRecoveryArea
    let message: String

    var id: SavedDataRecoveryArea { area }
}

struct SavedDataRecoveryPresentation: Equatable {
    let items: [SavedDataRecoveryItem]

    init(
        settingsErrorMessage: String? = nil,
        sidebarErrorMessage: String? = nil,
        sessionErrorMessage: String? = nil
    ) {
        items = [
            settingsErrorMessage.map { SavedDataRecoveryItem(area: .settings, message: $0) },
            sidebarErrorMessage.map { SavedDataRecoveryItem(area: .sidebar, message: $0) },
            sessionErrorMessage.map { SavedDataRecoveryItem(area: .session, message: $0) }
        ].compactMap { $0 }
    }
}

struct SavedDataRecoveryView: View {
    @Binding var restorePreviousSession: Bool
    let settingsErrorMessage: String?
    let sidebarErrorMessage: String?
    let sessionErrorMessage: String?
    let onResetSettings: () -> Void
    let onResetSidebar: () -> Void
    let onResetSession: () -> Void

    private var presentation: SavedDataRecoveryPresentation {
        SavedDataRecoveryPresentation(
            settingsErrorMessage: settingsErrorMessage,
            sidebarErrorMessage: sidebarErrorMessage,
            sessionErrorMessage: sessionErrorMessage
        )
    }

    var body: some View {
        Section("Startup") {
            Toggle("Restore Previous Session", isOn: $restorePreviousSession)
            Text("Reopens the last saved tabs, panes, and folders. Search, selection, Undo, and file operations are never restored.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if !presentation.items.isEmpty {
            Section("Saved Data Recovery") {
                ForEach(presentation.items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Label(item.area.title, systemImage: item.area.systemImage)
                                .font(.headline)
                            Spacer(minLength: 12)
                            Button("Reset", role: .destructive) {
                                reset(item.area)
                            }
                        }
                        Text(item.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text("The unreadable saved value is preserved until you reset this area.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func reset(_ area: SavedDataRecoveryArea) {
        switch area {
        case .settings: onResetSettings()
        case .sidebar: onResetSidebar()
        case .session: onResetSession()
        }
    }
}
