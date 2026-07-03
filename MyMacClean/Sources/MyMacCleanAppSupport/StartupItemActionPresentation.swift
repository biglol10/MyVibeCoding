import Foundation
import MyMacCleanCore

public enum StartupItemAction: Equatable, Sendable {
    case disable
    case enable
}

public struct StartupItemActionPresentation: Equatable, Sendable {
    public let action: StartupItemAction?
    public let buttonTitle: String
    public let applyingTitle: String
    public let systemImage: String
    public let helpText: String
    public let confirmationTitle: String
    public let confirmationMessage: String

    public init(item: StartupItem) {
        if item.isReadOnly {
            action = nil
            buttonTitle = "Read-only System Item"
            applyingTitle = buttonTitle
            systemImage = "lock"
            helpText = "System-wide launch items are shown for auditing only."
            confirmationTitle = buttonTitle
            confirmationMessage = helpText
        } else if item.state == .enabled {
            action = .disable
            buttonTitle = "Disable Startup Item"
            applyingTitle = "Disabling..."
            systemImage = "pause.circle"
            helpText = "Disabling renames the plist with a .mymacclean-disabled suffix. MyMacClean does not edit plist contents and does not call launchctl. If the agent is already loaded, it may keep running until next login or restart."
            confirmationTitle = "Disable Startup Item?"
            confirmationMessage = "This will rename \(item.label)'s plist with a .mymacclean-disabled suffix. MyMacClean does not call launchctl, so a currently loaded agent may keep running until next login or restart."
        } else if item.disabledByRename {
            action = .enable
            buttonTitle = "Enable Startup Item"
            applyingTitle = "Enabling..."
            systemImage = "play.circle"
            helpText = "Re-enabling restores the original plist filename. launchd may load it on the next login or restart."
            confirmationTitle = "Enable Startup Item?"
            confirmationMessage = "This will restore the original plist filename for \(item.label). launchd may not load it until next login or restart unless macOS loads it later."
        } else {
            action = nil
            buttonTitle = "Disabled by Plist Flag"
            applyingTitle = buttonTitle
            systemImage = "checkmark.circle"
            helpText = "This item is disabled inside the plist. MyMacClean will not edit plist contents."
            confirmationTitle = buttonTitle
            confirmationMessage = helpText
        }
    }
}
