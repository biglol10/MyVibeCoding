import Foundation
import MyMacCleanCore

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
        receipt.action.isStartupItemChange ? "Changed" : "Deleted"
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
        return "\(completedCount) deleted, \(remainingCount) remaining"
    }

    public var copyableReportText: String {
        var lines = [
            receipt.action.isStartupItemChange ? "MyMacClean Startup Item Report" : "MyMacClean Deletion Report",
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

        let errors = receipt.executionResults.compactMap { result -> String? in
            guard let errorMessage = result.errorMessage else { return nil }
            return "\(result.path) - \(errorMessage)"
        }

        if !errors.isEmpty {
            lines.append("")
            lines.append("Errors:")
            lines.append(contentsOf: errors)
        }

        return lines.joined(separator: "\n")
    }
}
