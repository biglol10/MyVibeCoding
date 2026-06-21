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
        .deleteHistory
    ]

    public static let roadmap: [SidebarDestination] = [
        .startupItems,
        .systemCleanup,
        .largeFiles,
        .maintenance
    ]

    public var title: String {
        switch self {
        case .applications: "Applications"
        case .orphanFiles: "Orphan Files"
        case .deleteHistory: "Delete History"
        case .startupItems: "Startup Items"
        case .systemCleanup: "System Cleanup"
        case .largeFiles: "Large Files"
        case .maintenance: "Maintenance"
        }
    }

    public var subtitle: String {
        switch self {
        case .applications:
            "Review installed apps and related files before permanent deletion."
        case .orphanFiles:
            "Find leftovers from apps that are no longer installed."
        case .deleteHistory:
            "Review completed deletions and failed cleanup attempts."
        case .startupItems:
            "Audit login items, launch agents, and background helpers."
        case .systemCleanup:
            "Find removable system junk without touching personal files."
        case .largeFiles:
            "Locate oversized files that are safe to review manually."
        case .maintenance:
            "Run routine checks for caches, logs, and stale indexes."
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
        case .startupItems: "Scan Login Items"
        case .systemCleanup: "Scan System Junk"
        case .largeFiles: "Find Large Files"
        case .maintenance: "Run Maintenance Check"
        }
    }
}
