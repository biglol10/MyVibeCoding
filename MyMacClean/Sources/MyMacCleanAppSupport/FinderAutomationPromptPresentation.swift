import Foundation
import MyMacCleanCore

public struct FinderAutomationPromptPresentation: Equatable, Sendable {
    public let appName: String

    public init(appName: String = "MyMacClean") {
        self.appName = appName
    }

    public var title: String {
        "Finder Permission May Be Needed"
    }

    public var message: String {
        "\(appName) may need Finder permission to move selected applications from /Applications to Trash when macOS blocks the standard Trash API. Continue only if you want \(appName) to request Finder access for this deletion."
    }

    public var primaryButtonTitle: String {
        "Continue and Request Finder Permission"
    }

    public var cancelButtonTitle: String {
        "Cancel"
    }

    public var settingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
    }

    public static func requiresPrompt(candidates: [RelatedFileCandidate], mode: DeletionMode) -> Bool {
        guard mode == .moveToTrash else { return false }
        return candidates.contains { candidate in
            candidate.kind == .appBundle && isSystemApplicationsBundle(candidate.url)
        }
    }

    private static func isSystemApplicationsBundle(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.hasPrefix("/Applications/") && path.hasSuffix(".app")
    }
}
