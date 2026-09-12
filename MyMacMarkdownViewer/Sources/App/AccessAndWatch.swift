import AppKit
import CoreServices
#if SWIFT_PACKAGE
import MyMarkdownCore
#endif

@MainActor
final class AccessManager {
    private var active: [String: URL] = [:]
    private var bookmarks: [String: Data] {
        get { UserDefaults.standard.dictionary(forKey: "fileBookmarks") as? [String: Data] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "fileBookmarks") }
    }
    var roots: [URL] { Array(active.values) }

    func grant(_ url: URL) {
        if active[url.path] == nil { _ = url.startAccessingSecurityScopedResource(); active[url.path] = url }
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            var saved = bookmarks; saved[url.path] = data; bookmarks = saved
        }
    }

    func restore(_ path: String) -> URL? {
        if let url = active[path] { return url }
        guard let data = bookmarks[path] else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        grant(url)
        return url
    }

    func canRead(_ url: URL) -> Bool {
        let target = url.resolvingSymlinksInPath().standardizedFileURL.path
        func includes(_ root: URL) -> Bool {
            let canonical = root.resolvingSymlinksInPath().standardizedFileURL.path
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir)
            return target == canonical || (isDir.boolValue && target.hasPrefix(canonical + "/"))
        }
        if active.values.contains(where: includes) { return true }
        for path in bookmarks.keys where target == path || target.hasPrefix(path + "/") {
            if let restored = restore(path), includes(restored) { return true }
        }
        return false
    }

    func retainAccess(for keep: [URL]) {
        let paths = keep.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        for (key, url) in active where !paths.contains(where: { $0 == key || $0.hasPrefix(key + "/") }) {
            url.stopAccessingSecurityScopedResource(); active.removeValue(forKey: key)
        }
    }
}

final class FileObservation: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue
    private let changed: @Sendable () -> Void
    init(url: URL, changed: @escaping @Sendable () -> Void) {
        presentedItemURL = url; self.changed = changed
        presentedItemOperationQueue = OperationQueue(); presentedItemOperationQueue.maxConcurrentOperationCount = 1
        super.init(); NSFileCoordinator.addFilePresenter(self)
    }
    func stop() { NSFileCoordinator.removeFilePresenter(self) }
    func presentedItemDidChange() { changed() }
    func presentedItemDidMove(to newURL: URL) { changed() }
    func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable (Error?) -> Void) { changed(); completionHandler(nil) }
}

final class FolderObservation {
    private final class Backend: @unchecked Sendable {
        private let lock = NSLock()
        private var active = true
        private let queue = DispatchQueue(label: "com.personal.MyMarkdownViewer.folder-observation")
        private var stream: FSEventStreamRef?
        private let changed: @MainActor () -> Void

        init(url: URL, changed: @escaping @MainActor () -> Void) {
            self.changed = changed
            queue.async { [self] in
                var context = FSEventStreamContext(
                    version: 0,
                    info: Unmanaged.passUnretained(self).toOpaque(),
                    retain: { info in
                        guard let info else { return nil }
                        _ = Unmanaged<Backend>.fromOpaque(info).retain()
                        return info
                    },
                    release: { info in
                        guard let info else { return }
                        Unmanaged<Backend>.fromOpaque(info).release()
                    },
                    copyDescription: nil
                )
                stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
                    guard let info else { return }
                    let backend = Unmanaged<Backend>.fromOpaque(info).takeUnretainedValue()
                    guard backend.isActive else { return }
                    Task { @MainActor in
                        guard backend.isActive else { return }
                        backend.changed()
                    }
                }, &context, [url.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes))
                if let stream {
                    guard isActive else { cleanup(stream); return }
                    FSEventStreamSetDispatchQueue(stream, queue)
                    guard FSEventStreamStart(stream) else { cleanup(stream); return }
                }
            }
        }

        private var isActive: Bool { lock.withLock { active } }

        func stop() {
            lock.withLock { active = false }
            queue.async { [self] in
                if let stream { cleanup(stream) }
            }
        }

        private func cleanup(_ stream: FSEventStreamRef) {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    private let backend: Backend
    init(url: URL, changed: @escaping @MainActor () -> Void) {
        backend = Backend(url: url, changed: changed)
    }
    func stop() { backend.stop() }
    deinit { backend.stop() }
}
