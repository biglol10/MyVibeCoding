import Foundation
@preconcurrency import QuickLookUI

@MainActor
public final class QuickLookPreviewController: NSObject, @preconcurrency QLPreviewPanelDataSource {
    public private(set) var previewURLs: [URL] = []
    public private(set) var selectedPreviewIndex = 0
    private var generation: UInt64 = 0

    public override init() {
        super.init()
    }

    @discardableResult
    public func updateSelection(_ url: URL?) -> UInt64 {
        updateSelection(url.map { [$0] } ?? [], selectedIndex: 0)
    }

    @discardableResult
    public func updateSelection(_ urls: [URL], selectedIndex: Int = 0) -> UInt64 {
        generation &+= 1
        previewURLs = urls.map(\.standardizedFileURL)
        self.selectedPreviewIndex = previewURLs.indices.contains(selectedIndex) ? selectedIndex : 0
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.reloadData()
        }
        return generation
    }

    public func clearSelection(ifGeneration expectedGeneration: UInt64) {
        guard generation == expectedGeneration else { return }
        previewURLs = []
        selectedPreviewIndex = 0
        if QLPreviewPanel.sharedPreviewPanelExists() {
            QLPreviewPanel.shared()?.reloadData()
        }
    }

    public func togglePanel() {
        guard !previewURLs.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = selectedPreviewIndex
        panel.makeKeyAndOrderFront(nil)
    }

    public func closePanel() {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    public func previewPanel(
        _ panel: QLPreviewPanel!,
        previewItemAt index: Int
    ) -> (any QLPreviewItem)! {
        guard previewURLs.indices.contains(index) else { return nil }
        return previewURLs[index] as NSURL
    }
}
