import Foundation
import Observation
import MyMacCleanCore

@MainActor
@Observable
public final class StartupItemsViewModel {
    private let scanner: StartupItemScanner
    private let controller: StartupItemController

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

    public init(
        scanner: StartupItemScanner = StartupItemScanner(),
        controller: StartupItemController = StartupItemController()
    ) {
        self.scanner = scanner
        self.controller = controller
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
            reconcileSelection()
        } catch {
            hasScanned = true
            errorMessage = error.localizedDescription
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
        await applyChange {
            try controller.disable(selectedItem)
        }
    }

    public func enableSelectedItem() async {
        guard !isApplyingChange else { return }
        guard let selectedItem else {
            errorMessage = "Select a startup item first."
            return
        }
        await applyChange {
            try controller.enable(selectedItem)
        }
    }

    private func applyChange(_ operation: () throws -> URL) async {
        isApplyingChange = true
        defer { isApplyingChange = false }
        do {
            let movedURL = try operation()
            items = try await scanner.scan()
            selectedItemID = items.first { $0.plistURL == movedURL }?.id ?? items.first?.id
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
