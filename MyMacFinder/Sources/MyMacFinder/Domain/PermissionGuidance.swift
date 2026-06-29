import Foundation

public struct SandboxPolicySummary: Equatable, Sendable {
    public let isSandboxed: Bool

    public init(isSandboxed: Bool) {
        self.isSandboxed = isSandboxed
    }

    public static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SandboxPolicySummary {
        SandboxPolicySummary(isSandboxed: environment["APP_SANDBOX_CONTAINER_ID"] != nil)
    }

    public var statusTitle: String {
        isSandboxed ? "Sandboxed" : "Unrestricted"
    }

    public var detail: String {
        if isSandboxed {
            return "macOS sandbox rules may require user-selected file access or security-scoped bookmarks."
        }
        return "This build is not app-sandboxed. Permission failures usually come from macOS privacy controls such as Full Disk Access."
    }
}

public enum PermissionRecoveryAction: String, Equatable, Sendable {
    case chooseFolder
    case openPrivacySettings
    case none
}

public struct PermissionGuidance: Equatable, Sendable {
    public static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )!

    public let message: String
    public let recoveryAction: PermissionRecoveryAction

    public var primaryActionTitle: String? {
        switch recoveryAction {
        case .chooseFolder:
            return "Choose Folder..."
        case .openPrivacySettings:
            return "Open Privacy Settings"
        case .none:
            return nil
        }
    }

    public init(error: ExplorerError, sandbox: SandboxPolicySummary = .current()) {
        switch error {
        case .permissionDenied(let path):
            self.message = Self.permissionDeniedMessage(path: path, sandbox: sandbox)
            self.recoveryAction = sandbox.isSandboxed ? .chooseFolder : .openPrivacySettings
        default:
            self.message = error.localizedDescription
            self.recoveryAction = .none
        }
    }

    private static func permissionDeniedMessage(path: String, sandbox: SandboxPolicySummary) -> String {
        if sandbox.isSandboxed {
            return """
            Permission denied: \(path)

            This app is sandboxed. Choose the folder in MyMacFinder to grant access, or adjust macOS Privacy settings.
            """
        }

        return """
        Permission denied: \(path)

        macOS may be blocking this folder. Grant MyMacFinder Full Disk Access, then refresh or reopen the folder.
        """
    }
}
