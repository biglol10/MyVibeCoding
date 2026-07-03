import Foundation
import Observation
import MyMacCleanCore

@MainActor
@Observable
public final class StartupItemsViewModel {
    private let scanner: StartupItemScanner
    private let controller: StartupItemController
    private let receiptStore: DeletionReceiptStore

    public var items: [StartupItem] = []
    public var selectedItemID: StartupItem.ID?
    public var searchText = "" {
        didSet {
            reconcileSelection()
        }
    }
    public var isScanning = false
    public var isApplyingChange = false
    public var hasScanned = false
    public var errorMessage: String?
    public var statusMessage: String?

    public init(
        scanner: StartupItemScanner = StartupItemScanner(),
        controller: StartupItemController = StartupItemController(),
        receiptStore: DeletionReceiptStore = .default()
    ) {
        self.scanner = scanner
        self.controller = controller
        self.receiptStore = receiptStore
    }

    public var visibleItems: [StartupItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.label.lowercased().contains(query)
                || item.ownerName.lowercased().contains(query)
                || item.plistURL.path.lowercased().contains(query)
                || item.scope.title.lowercased().contains(query)
                || item.state.title.lowercased().contains(query)
        }
    }

    public var selectedItem: StartupItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
    }

    public func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            items = try await scanner.scan()
            hasScanned = true
            errorMessage = nil
            statusMessage = nil
            reconcileSelection()
        } catch {
            hasScanned = true
            errorMessage = error.localizedDescription
            statusMessage = nil
            items = []
            selectedItemID = nil
        }
    }

    public func selectItem(id: StartupItem.ID?) {
        selectedItemID = id
    }

    public func disableSelectedItem() async {
        guard !isApplyingChange else { return }
        guard let selectedItem else {
            errorMessage = "Select a startup item first."
            return
        }
        await applyChange(item: selectedItem, action: .startupItemDisable) {
            try controller.disable(selectedItem)
        }
    }

    public func enableSelectedItem() async {
        guard !isApplyingChange else { return }
        guard let selectedItem else {
            errorMessage = "Select a startup item first."
            return
        }
        await applyChange(item: selectedItem, action: .startupItemEnable) {
            try controller.enable(selectedItem)
        }
    }

    private func applyChange(item: StartupItem, action: DeletionAction, _ operation: () throws -> URL) async {
        isApplyingChange = true
        defer { isApplyingChange = false }
        do {
            let sourceURL = item.plistURL
            let movedURL = try operation()
            items = try await scanner.scan()
            selectedItemID = items.first { $0.plistURL == movedURL }?.id ?? items.first?.id
            errorMessage = nil
            let receipt = receipt(for: item, action: action, sourceURL: sourceURL)
            do {
                try receiptStore.append(receipt)
                statusMessage = successMessage(for: action)
            } catch {
                statusMessage = nil
                errorMessage = "Startup item changed, but history could not be saved: \(error.localizedDescription)"
            }
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
        }
    }

    private func receipt(for item: StartupItem, action: DeletionAction, sourceURL: URL) -> DeletionReceipt {
        DeletionReceipt(
            appName: item.label,
            bundleIdentifier: nil,
            bundlePath: sourceURL.path,
            action: action,
            selectedCandidates: [
                DeletionReceiptCandidate(
                    path: sourceURL.path,
                    kind: item.scope == .globalLaunchDaemon ? .launchDaemon : .launchAgent,
                    size: 0,
                    safety: .review,
                    evidence: []
                )
            ],
            executionResults: [
                DeletionItemResult(path: sourceURL.path, success: true, errorMessage: nil)
            ],
            verificationResults: [
                DeletionVerificationResult(path: sourceURL.path, status: .deleted, errorMessage: nil)
            ],
            confirmationMatched: true
        )
    }

    private func successMessage(for action: DeletionAction) -> String {
        switch action {
        case .startupItemDisable:
            "Startup item was disabled. It can keep running until you log out or restart because MyMacClean only renames the plist. The change is recorded in history."
        case .startupItemEnable:
            "Startup item was re-enabled. The change is recorded in history."
        default:
            "Startup item change is recorded in history."
        }
    }

    private func reconcileSelection() {
        let visibleIDs = Set(visibleItems.map(\.id))
        if let selectedItemID, visibleIDs.contains(selectedItemID) {
            return
        }
        selectedItemID = visibleItems.first?.id
    }
}
