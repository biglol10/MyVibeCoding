import Foundation
import MyMacCleanCore

public struct DeletionErrorLog: Equatable, Sendable {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }

    public var line: String {
        "\(path) - \(message)"
    }
}

public struct DeletionReportViewModel: Equatable, Sendable {
    public let receipt: DeletionReceipt

    public init(receipt: DeletionReceipt) {
        self.receipt = receipt
    }

    public var statusTitle: String {
        if receipt.action.isStartupItemChange {
            if receipt.executionResults.contains(where: { !$0.success }) {
                return "Startup item change failed"
            }
            if remainingCount > 0 {
                return "Startup item changed with remaining items"
            }
            return "Startup item changed"
        }

        let hasDeletedItems = receipt.verificationResults.contains { $0.status == .deleted }
        let hasRemainingItems = receipt.verificationResults.contains { $0.status == .stillExists || $0.status == .permissionDenied }
        if receipt.action == .appReset {
            if hasDeletedItems && hasRemainingItems {
                return "App data reset with remaining items"
            }
            if receipt.executionResults.contains(where: { !$0.success }) {
                return "App data reset failed"
            }
            if hasRemainingItems {
                return "App data reset with remaining items"
            }
            return "App data reset and verified"
        }
        if hasDeletedItems && hasRemainingItems {
            return "Deleted with remaining items"
        }
        if receipt.executionResults.contains(where: { !$0.success }) {
            return "Deletion failed"
        }
        if hasRemainingItems {
            return "Deleted with remaining items"
        }
        return "Deleted and verified"
    }

    public var deletedCount: Int {
        receipt.verificationResults.filter { $0.status == .deleted }.count
    }

    public var completedCountTitle: String {
        if receipt.action.isStartupItemChange {
            return "Changed"
        }
        return receipt.action == .appReset ? "Reset" : "Deleted"
    }

    public var completedCount: Int {
        deletedCount
    }

    public var remainingCount: Int {
        receipt.verificationResults.filter { $0.status == .stillExists || $0.status == .permissionDenied }.count
    }

    public var remainingPaths: [String] {
        receipt.verificationResults
            .filter { $0.status == .stillExists || $0.status == .permissionDenied }
            .map(\.path)
    }

    public var summaryLine: String {
        if receipt.action.isStartupItemChange {
            return "\(completedCount) changed, \(remainingCount) remaining"
        }
        if receipt.action == .appReset {
            return "\(completedCount) reset, \(remainingCount) remaining"
        }
        return "\(completedCount) deleted, \(remainingCount) remaining"
    }

    public var isFullySuccessful: Bool {
        remainingCount == 0 && errorLogs.isEmpty
    }

    public var errorLogs: [DeletionErrorLog] {
        let executionErrors = receipt.executionResults.compactMap { result -> DeletionErrorLog? in
            guard let errorMessage = result.errorMessage, !result.success else { return nil }
            return DeletionErrorLog(path: result.path, message: errorMessage)
        }

        let verificationErrors = receipt.verificationResults.compactMap { result -> DeletionErrorLog? in
            if let errorMessage = result.errorMessage {
                return DeletionErrorLog(path: result.path, message: errorMessage)
            }
            if result.status == .permissionDenied {
                return DeletionErrorLog(path: result.path, message: "Permission denied")
            }
            return nil
        }

        return executionErrors + verificationErrors
    }

    public var errorLogLines: [String] {
        errorLogs.map(\.line)
    }

    public var hasPermissionFailure: Bool {
        receipt.verificationResults.contains { $0.status == .permissionDenied }
            || errorLogs.contains { log in
                Self.isPermissionFailureMessage(log.message)
            }
    }

    public var copyableReportText: String {
        let reportTitle: String
        if receipt.action.isStartupItemChange {
            reportTitle = "MyMacClean Startup Item Report"
        } else if receipt.action == .appReset {
            reportTitle = "MyMacClean App Data Reset Report"
        } else {
            reportTitle = "MyMacClean Deletion Report"
        }

        var lines = [
            reportTitle,
            "App: \(receipt.appName)",
            "Bundle ID: \(receipt.bundleIdentifier ?? "Unknown")",
            "Action: \(receipt.action.rawValue)",
            "Status: \(statusTitle)",
            "\(completedCountTitle): \(completedCount)",
            "Remaining: \(remainingCount)"
        ]

        if !remainingPaths.isEmpty {
            lines.append("")
            lines.append("Remaining Paths:")
            lines.append(contentsOf: remainingPaths)
        }

        if !errorLogLines.isEmpty {
            lines.append("")
            lines.append("Errors:")
            lines.append(contentsOf: errorLogLines)
        }

        return lines.joined(separator: "\n")
    }

    private static func isPermissionFailureMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("permission")
            || normalized.contains("operation not permitted")
            || normalized.contains("full disk access")
            || normalized.contains("not authorized")
    }
}
