import CoreServices
import Foundation

@MainActor
public protocol DirectoryWatching: AnyObject {
    func startWatching(_ urls: [URL], onChange: @escaping @Sendable () -> Void)
    func stopWatching()
}

public extension DirectoryWatching {
    func startWatching(_ url: URL, onChange: @escaping @Sendable () -> Void) {
        startWatching([url], onChange: onChange)
    }
}

@MainActor
public final class DirectoryWatcherService: DirectoryWatching {
    private var stream: FSEventStreamRef?
    private var callbackBox: CallbackBox?

    public init() {}

    deinit {
        MainActor.assumeIsolated {
            stopWatching()
        }
    }

    public func startWatching(_ urls: [URL], onChange: @escaping @Sendable () -> Void) {
        stopWatching()
        let paths = Array(Set(urls.map { $0.standardizedFileURL.path })).sorted()
        guard !paths.isEmpty else {
            return
        }

        let callbackBox = CallbackBox(onChange: onChange)
        self.callbackBox = callbackBox
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(callbackBox).toOpaque())
        var streamContext = FSEventStreamContext(
            version: 0,
            info: context,
            retain: { contextInfo in
                guard let contextInfo else {
                    return nil
                }
                return UnsafeRawPointer(Unmanaged<CallbackBox>.fromOpaque(contextInfo).retain().toOpaque())
            },
            release: { contextInfo in
                guard let contextInfo else {
                    return
                }
                Unmanaged<CallbackBox>.fromOpaque(contextInfo).release()
            },
            copyDescription: nil
        )

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, contextInfo, _, _, _, _ in
                guard let contextInfo else {
                    return
                }
                let box = Unmanaged<CallbackBox>.fromOpaque(contextInfo).takeUnretainedValue()
                box.onChange()
            },
            &streamContext,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    public func stopWatching() {
        guard let stream else {
            callbackBox = nil
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamSetDispatchQueue(stream, nil)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        callbackBox = nil
    }

    private final class CallbackBox {
        let onChange: @Sendable () -> Void

        init(onChange: @escaping @Sendable () -> Void) {
            self.onChange = onChange
        }
    }
}
