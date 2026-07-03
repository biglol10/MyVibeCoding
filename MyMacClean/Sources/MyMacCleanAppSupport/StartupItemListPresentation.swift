import Foundation
import MyMacCleanCore

public struct StartupItemListPresentation: Equatable, Sendable {
    public let stateBadgeTitle: String
    public let scopeBadgeTitle: String
    public let attentionBadgeTitle: String?

    public init(item: StartupItem) {
        stateBadgeTitle = item.state.title

        switch item.scope {
        case .userLaunchAgent:
            scopeBadgeTitle = "User"
        case .globalLaunchAgent:
            scopeBadgeTitle = "Global"
        case .globalLaunchDaemon:
            scopeBadgeTitle = "Daemon"
        }

        if item.hasMissingTarget {
            attentionBadgeTitle = "Missing"
        } else if item.isReadOnly {
            attentionBadgeTitle = "Read-only"
        } else {
            attentionBadgeTitle = nil
        }
    }
}
