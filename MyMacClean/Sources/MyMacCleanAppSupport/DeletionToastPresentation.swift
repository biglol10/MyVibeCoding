import Foundation

public enum DeletionToastSeverity: Equatable, Sendable {
    case success
    case error
}

public struct DeletionToastPresentation: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let severity: DeletionToastSeverity
    public let title: String
    public let message: String
    public let detailLines: [String]
    public let showsFullDiskAccessAction: Bool
    public let showsAppManagementSettingsAction: Bool

    public init(
        id: UUID = UUID(),
        severity: DeletionToastSeverity,
        title: String,
        message: String,
        detailLines: [String] = [],
        showsFullDiskAccessAction: Bool = false,
        showsAppManagementSettingsAction: Bool = false
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.message = message
        self.detailLines = detailLines
        self.showsFullDiskAccessAction = showsFullDiskAccessAction
        self.showsAppManagementSettingsAction = showsAppManagementSettingsAction
    }

    public init(report: DeletionReportViewModel, id: UUID = UUID()) {
        self.id = id
        self.severity = report.isFullySuccessful ? .success : .error
        if report.receipt.action == .appReset {
            self.title = report.isFullySuccessful ? "App data reset succeeded" : "App data reset failed"
        } else {
            self.title = report.isFullySuccessful ? "Deletion succeeded" : "Deletion failed"
        }
        self.message = report.hasAppManagementFailure
            ? "\(report.summaryLine). App Management permission or administrator authentication may be required."
            : report.summaryLine
        self.detailLines = report.errorLogLines.isEmpty
            ? report.remainingPaths.map { "Remaining: \($0)" }
            : report.errorLogLines
        self.showsFullDiskAccessAction = report.hasFullDiskAccessFailure
        self.showsAppManagementSettingsAction = report.hasAppManagementFailure
    }

    public static func error(message: String, report: DeletionReportViewModel? = nil) -> DeletionToastPresentation {
        DeletionToastPresentation(
            severity: .error,
            title: report?.isFullySuccessful == true ? "Deletion completed with warning" : "Deletion failed",
            message: message,
            detailLines: report?.errorLogLines ?? [],
            showsFullDiskAccessAction: report?.hasFullDiskAccessFailure ?? isPermissionFailureMessage(message),
            showsAppManagementSettingsAction: report?.hasAppManagementFailure ?? isAppManagementFailureMessage(message)
        )
    }

    public var fullDiskAccessButtonTitle: String {
        "Open Full Disk Access Settings"
    }

    public var appManagementSettingsButtonTitle: String {
        "Open App Management Settings"
    }

    private static func isPermissionFailureMessage(_ message: String) -> Bool {
        if isAppManagementFailureMessage(message) {
            return false
        }
        let normalized = message.lowercased()
        return normalized.contains("permission")
            || normalized.contains("operation not permitted")
            || normalized.contains("full disk access")
            || normalized.contains("not authorized")
    }

    private static func isAppManagementFailureMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("app bundle")
            || normalized.contains("app management")
    }
}
