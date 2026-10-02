import AppKit

/// Queues launch-time events until session restoration finishes, then processes them in order.
@MainActor
final class ExternalOpenCoordinator {
    private var store: ExplorerStore?
    private var startupTask: Task<Void, Never>?
    private var pendingURLs: [URL] = []
    private var isReady = false
    private var isDraining = false
    var showWindow: (() -> Void)?

    func start(store: ExplorerStore) async {
        if let startupTask {
            await startupTask.value
            return
        }
        self.store = store
        let task = Task { @MainActor in
            await store.cleanupExpiredArchiveArtifacts()
            await store.loadInitialDirectory()
            isReady = true
            drain()
        }
        startupTask = task
        await task.value
    }

    func enqueue(_ urls: [URL]) {
        pendingURLs.append(contentsOf: urls)
        showWindow?()
        drain()
    }

    private func drain() {
        guard isReady, !isDraining, let store, !pendingURLs.isEmpty else { return }
        isDraining = true
        Task { @MainActor in
            while !pendingURLs.isEmpty {
                let url = pendingURLs.removeFirst()
                await store.openExternalURL(url)
            }
            isDraining = false
        }
    }
}

@MainActor
final class ExternalOpenAppDelegate: NSObject, NSApplicationDelegate {
    let receiver = ExternalOpenCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receiver.enqueue(urls)
        application.activate(ignoringOtherApps: true)
    }

    @objc(openInPaneHarbor:userData:error:)
    func openInPaneHarbor(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        do {
            receiver.enqueue(try ExternalOpenRequest.fileURLs(from: pasteboard))
            NSApp.activate(ignoringOtherApps: true)
        } catch let failure {
            error.pointee = failure.localizedDescription as NSString
        }
    }
}
