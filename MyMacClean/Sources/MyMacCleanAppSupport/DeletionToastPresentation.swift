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

    public init(
        id: UUID = UUID(),
        severity: DeletionToastSeverity,
        title: String,
        message: String,
        detailLines: [String] = []
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.message = message
        self.detailLines = detailLines
    }

    public init(report: DeletionReportViewModel, id: UUID = UUID()) {
        self.id = id
        self.severity = report.isFullySuccessful ? .success : .error
        self.title = report.isFullySuccessful ? "Deletion succeeded" : "Deletion failed"
        self.message = report.summaryLine
        self.detailLines = report.errorLogLines.isEmpty
            ? report.remainingPaths.map { "Remaining: \($0)" }
            : report.errorLogLines
    }

    public static func error(message: String, report: DeletionReportViewModel? = nil) -> DeletionToastPresentation {
        DeletionToastPresentation(
            severity: .error,
            title: report?.isFullySuccessful == true ? "Deletion completed with warning" : "Deletion failed",
            message: message,
            detailLines: report?.errorLogLines ?? []
        )
    }
}
