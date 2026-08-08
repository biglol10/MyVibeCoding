public enum SidebarDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
    case applications
    case orphanFiles
    case deleteHistory
    case startupItems
    case systemCleanup
    case largeFiles
    case maintenance

    public var id: Self { self }

    public static let currentRelease: [SidebarDestination] = [
        .applications,
        .orphanFiles,
        .deleteHistory,
        .startupItems,
        .largeFiles,
        .maintenance
    ]

    public static let roadmap: [SidebarDestination] = [
        .systemCleanup
    ]

    public var title: String {
        switch self {
        case .applications: "Applications"
        case .orphanFiles: "Orphan Files"
        case .deleteHistory: "Delete History"
        case .startupItems: "Startup Items"
        case .systemCleanup: "System Cleanup"
        case .largeFiles: "Large Files"
        case .maintenance: "Developer Cache"
        }
    }

    public var subtitle: String {
        switch self {
        case .applications:
            "Review installed apps and related files before moving selected items to Trash."
        case .orphanFiles:
            "Find leftovers from apps that are no longer installed."
        case .deleteHistory:
            "Review completed deletions and failed cleanup attempts."
        case .startupItems:
            "Audit login items, launch agents, and background helpers."
        case .systemCleanup:
            "Find removable system junk without touching personal files."
        case .largeFiles:
            "Find oversized files for manual review before moving anything to Trash."
        case .maintenance:
            "Review build caches that can be regenerated."
        }
    }

    public var systemImage: String {
        switch self {
        case .applications: "app.dashed"
        case .orphanFiles: "folder.badge.questionmark"
        case .deleteHistory: "clock"
        case .startupItems: "bolt"
        case .systemCleanup: "sparkles"
        case .largeFiles: "internaldrive"
        case .maintenance: "wrench.adjustable"
        }
    }

    public var primaryActionTitle: String {
        switch self {
        case .applications: "Scan Selected"
        case .orphanFiles: "Scan Leftovers"
        case .deleteHistory: "Refresh History"
        case .startupItems: "Scan Startup Items"
        case .systemCleanup: "Scan System Junk"
        case .largeFiles: "Scan Large Files"
        case .maintenance: "Scan Developer Caches"
        }
    }
}
