import Foundation
import MyMacCleanCore

public enum DeletionHistoryStatus: Equatable, Sendable {
    case verified
    case needsReview
    case failed

    public var title: String {
        switch self {
        case .verified: "Verified"
        case .needsReview: "Needs Review"
        case .failed: "Failed"
        }
    }
}

public struct DeletionHistoryReceiptSummary: Equatable, Sendable {
    public let receipt: DeletionReceipt

    public init(receipt: DeletionReceipt) {
        self.receipt = receipt
    }

    public var status: DeletionHistoryStatus {
        if hasExecutionFailure && deletedCount == 0 {
            return .failed
        }
        if remainingCount > 0 || hasExecutionFailure {
            return .needsReview
        }
        return .verified
    }

    public var statusTitle: String {
        if receipt.action.isStartupItemChange && status == .verified {
            return "Changed"
        }
        return status.title
    }

    public var actionTitle: String {
        switch receipt.action {
        case .uninstall: "Uninstall"
        case .appReset: "App Data Reset"
        case .orphanCleanup: "Orphan Cleanup"
        case .largeFileCleanup: "Large File Cleanup"
        case .developerCacheCleanup: "Developer Cache Cleanup"
        case .startupItemDisable: "Startup Item Disabled"
        case .startupItemEnable: "Startup Item Enabled"
        }
    }

    public var primaryCountTitle: String {
        if receipt.action.isStartupItemChange {
            return "Changed"
        }
        return receipt.action == .appReset ? "Reset" : "Deleted"
    }

    public var primaryCount: Int {
        if receipt.action.isStartupItemChange {
            return receipt.executionResults.filter(\.success).count
        }
        return deletedCount
    }

    public var deletedCount: Int {
        receipt.verificationResults.filter { $0.status == .deleted }.count
    }

    public var remainingCount: Int {
        remainingPaths.count
    }

    public var remainingPaths: [String] {
        receipt.verificationResults
            .filter { $0.status == .stillExists || $0.status == .permissionDenied }
            .map(\.path)
    }

    private var hasExecutionFailure: Bool {
        receipt.executionResults.contains { !$0.success }
    }
}
