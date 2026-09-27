import Foundation
import MyMacCleanCore

public struct AppManagementPromptPresentation: Equatable, Sendable {
    public let appName: String

    public init(appName: String = "MyMacClean") {
        self.appName = appName
    }

    public var title: String {
        "App Management Permission May Be Needed"
    }

    public var message: String {
        "\(appName) uses macOS App Management permission to move selected apps from /Applications to Trash. Full Disk Access does not grant this permission, and macOS may still request an administrator password for apps owned by another user."
    }

    public var primaryButtonTitle: String {
        "Open App Management Settings"
    }

    public var cancelButtonTitle: String {
        "Cancel"
    }

    public var settingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!
    }
}
