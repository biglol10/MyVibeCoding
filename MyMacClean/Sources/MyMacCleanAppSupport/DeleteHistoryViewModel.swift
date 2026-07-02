import Foundation
import Observation
import MyMacCleanCore

@MainActor
@Observable
public final class DeleteHistoryViewModel {
    private let receiptStore: DeletionReceiptStore

    public var receipts: [DeletionReceipt] = []
    public var searchText = "" {
        didSet { reconcileSelection() }
    }
    public var selectedReceiptID: DeletionReceipt.ID?
    public var errorMessage: String?
    public var isClearHistoryConfirmationPresented = false

    public init(receiptStore: DeletionReceiptStore = .default()) {
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

    public var selectedReceipt: DeletionReceipt? {
        guard let selectedReceiptID else { return nil }
        return filteredReceipts.first { $0.id == selectedReceiptID }
    }

    public func load() async {
        do {
            receipts = try receiptStore.readReceipts()
                .sorted { $0.completedAt > $1.completedAt }
            reconcileSelection()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func selectReceipt(id: DeletionReceipt.ID?) {
        guard let id, filteredReceipts.contains(where: { $0.id == id }) else {
            selectedReceiptID = nil
            return
        }
        selectedReceiptID = id
    }

    public func requestClearHistory() {
        guard !receipts.isEmpty else { return }
        isClearHistoryConfirmationPresented = true
    }

    public func cancelClearHistory() {
        isClearHistoryConfirmationPresented = false
    }

    public func confirmClearHistory() {
        guard isClearHistoryConfirmationPresented else { return }
        clearHistory()
    }

    public func clearHistory() {
        do {
            try receiptStore.clear()
            receipts = []
            selectedReceiptID = nil
            isClearHistoryConfirmationPresented = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reconcileSelection() {
        let visibleReceipts = filteredReceipts
        if let selectedReceiptID, visibleReceipts.contains(where: { $0.id == selectedReceiptID }) {
            return
        }
        selectedReceiptID = visibleReceipts.first?.id
    }
}
