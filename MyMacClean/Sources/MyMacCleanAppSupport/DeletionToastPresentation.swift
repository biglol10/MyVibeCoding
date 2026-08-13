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
    public let showsAutomationSettingsAction: Bool

    public init(
        id: UUID = UUID(),
        severity: DeletionToastSeverity,
        title: String,
        message: String,
        detailLines: [String] = [],
        showsFullDiskAccessAction: Bool = false,
        showsAutomationSettingsAction: Bool = false
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.message = message
        self.detailLines = detailLines
        self.showsFullDiskAccessAction = showsFullDiskAccessAction
        self.showsAutomationSettingsAction = showsAutomationSettingsAction
    }

    public init(report: DeletionReportViewModel, id: UUID = UUID()) {
        self.id = id
        self.severity = report.isFullySuccessful ? .success : .error
        if report.receipt.action == .appReset {
            self.title = report.isFullySuccessful ? "App data reset succeeded" : "App data reset failed"
        } else {
            self.title = report.isFullySuccessful ? "Deletion succeeded" : "Deletion failed"
        }
        self.message = report.summaryLine
        self.detailLines = report.errorLogLines.isEmpty
            ? report.remainingPaths.map { "Remaining: \($0)" }
            : report.errorLogLines
        self.showsFullDiskAccessAction = report.hasPermissionFailure
        self.showsAutomationSettingsAction = report.errorLogs.contains { log in
            Self.isAutomationFailureMessage(log.message)
        }
    }

    public static func error(message: String, report: DeletionReportViewModel? = nil) -> DeletionToastPresentation {
        DeletionToastPresentation(
            severity: .error,
            title: report?.isFullySuccessful == true ? "Deletion completed with warning" : "Deletion failed",
            message: message,
            detailLines: report?.errorLogLines ?? [],
            showsFullDiskAccessAction: report?.hasPermissionFailure ?? isPermissionFailureMessage(message),
            showsAutomationSettingsAction: report.map { report in
                report.errorLogs.contains { Self.isAutomationFailureMessage($0.message) }
            } ?? isAutomationFailureMessage(message)
        )
    }

    public var fullDiskAccessButtonTitle: String {
        "Open Full Disk Access Settings"
    }

    public var automationSettingsButtonTitle: String {
        "Open Automation Settings"
    }

    private static func isPermissionFailureMessage(_ message: String) -> Bool {
        if isAutomationFailureMessage(message) {
            return false
        }
        let normalized = message.lowercased()
        return normalized.contains("permission")
            || normalized.contains("operation not permitted")
            || normalized.contains("full disk access")
            || normalized.contains("not authorized")
    }

    private static func isAutomationFailureMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("finder automation")
            || normalized.contains("automation")
            || normalized.contains("apple events")
            || normalized.contains("appleevents")
    }
}
