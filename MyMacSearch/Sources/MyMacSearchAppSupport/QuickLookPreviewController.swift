import Foundation
@preconcurrency import QuickLookUI

@MainActor
public final class QuickLookPreviewController: NSObject, @preconcurrency QLPreviewPanelDataSource {
    public private(set) var previewURL: URL?
    private var generation: UInt64 = 0

    public override init() {
        super.init()
    }

    @discardableResult
    public func updateSelection(_ url: URL?) -> UInt64 {
        generation &+= 1
        previewURL = url?.standardizedFileURL
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.reloadData()
        }
        return generation
    }

    public func clearSelection(ifGeneration expectedGeneration: UInt64) {
        guard generation == expectedGeneration else { return }
        previewURL = nil
        if QLPreviewPanel.sharedPreviewPanelExists() {
            QLPreviewPanel.shared()?.reloadData()
        }
    }

    public func togglePanel() {
        guard previewURL != nil, let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    public func closePanel() {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    public func previewPanel(
        _ panel: QLPreviewPanel!,
        previewItemAt index: Int
    ) -> (any QLPreviewItem)! {
        guard index == 0, let previewURL else { return nil }
        return previewURL as NSURL
    }
}
