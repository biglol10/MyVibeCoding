import Foundation
import Observation
import MyMacCleanCore

@MainActor
@Observable
public final class DeleteHistoryViewModel {
    private let receiptStore: DeletionReceiptStore

    public var receipts: [DeletionReceipt] = []
    public var searchText = ""
    public var errorMessage: String?

    public init(receiptStore: DeletionReceiptStore = DeletionReceiptStore(
        fileURL: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MyMacClean/deletion-receipts.jsonl")
    )) {
        self.receiptStore = receiptStore
    }

    public var filteredReceipts: [DeletionReceipt] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return receipts }
        return receipts.filter { receipt in
            receipt.appName.lowercased().contains(query)
                || (receipt.bundleIdentifier?.lowercased().contains(query) ?? false)
                || receipt.bundlePath.lowercased().contains(query)
                || receipt.selectedCandidates.contains { $0.path.lowercased().contains(query) }
        }
    }

    public func load() async {
        do {
            receipts = try receiptStore.readReceipts()
                .sorted { $0.completedAt > $1.completedAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func clearHistory() {
        do {
            try receiptStore.clear()
            receipts = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
