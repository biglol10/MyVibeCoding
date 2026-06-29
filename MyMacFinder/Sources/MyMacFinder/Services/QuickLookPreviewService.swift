import Foundation
import Quartz

@MainActor
public protocol QuickLooking: AnyObject {
    func preview(_ urls: [URL]) throws
}

@MainActor
public final class QuickLookPreviewService: NSObject, QuickLooking, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var urls: [URL] = []

    public override init() {
        super.init()
    }

    public func preview(_ urls: [URL]) throws {
        guard !urls.isEmpty else {
            return
        }

        self.urls = urls
        guard let panel = QLPreviewPanel.shared() else {
            throw ExplorerError.readFailed("Quick Look is unavailable.")
        }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}
