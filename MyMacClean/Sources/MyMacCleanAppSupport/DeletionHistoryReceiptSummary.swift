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
        status.title
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
