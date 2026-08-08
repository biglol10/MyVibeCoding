import Foundation
import Quartz

@MainActor
public protocol QuickLooking: AnyObject {
    func preview(_ session: QuickLookPreviewSession) throws
}

@MainActor
public final class QuickLookPreviewService: NSObject, QuickLooking, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    typealias Presenter = @MainActor (QuickLookPreviewService) throws -> Void

    private let presenter: Presenter
    private var currentSession: QuickLookPreviewSession?
    private weak var previewPanel: QLPreviewPanel?

    public override init() {
        self.presenter = Self.present
        super.init()
    }

    init(presenter: @escaping Presenter) {
        self.presenter = presenter
        super.init()
    }

    public func preview(_ session: QuickLookPreviewSession) throws {
        releaseCurrentSession()

        guard !session.urls.isEmpty else {
            session.release()
            return
        }

        currentSession = session
        do {
            try presenter(self)
        } catch {
            currentSession = nil
            throw error
        }
    }

    private static func present(_ service: QuickLookPreviewService) throws {
        guard let panel = QLPreviewPanel.shared() else {
            throw ExplorerError.readFailed("Quick Look is unavailable.")
        }
        service.previewPanel = panel
        panel.dataSource = service
        panel.delegate = service
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        currentSession?.urls.count ?? 0
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        currentSession?.urls[index] as NSURL?
    }

    public func windowWillClose(_ notification: Notification) {
        guard let closingPanel = notification.object as? QLPreviewPanel,
              closingPanel === previewPanel else {
            return
        }

        closingPanel.dataSource = nil
        closingPanel.delegate = nil
        previewPanel = nil
        releaseCurrentSession()
    }

    private func releaseCurrentSession() {
        let session = currentSession
        currentSession = nil
        session?.release()
    }
}
