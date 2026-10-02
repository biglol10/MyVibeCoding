import Foundation

@MainActor
public final class QuickLookPreviewSession {
    public let urls: [URL]
    private var releaseAction: (@MainActor @Sendable () -> Void)?

    public init(urls: [URL], release: @escaping @MainActor @Sendable () -> Void) {
        self.urls = urls
        self.releaseAction = release
    }

    public func release() {
        let action = releaseAction
        releaseAction = nil
        action?()
    }
}
