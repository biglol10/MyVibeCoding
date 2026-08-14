import CoreServices
import Foundation

public enum FSEventsWatcherError: Error, LocalizedError, Equatable, Sendable {
    case streamCreationFailed
    case streamStartFailed

    public var errorDescription: String? {
        switch self {
        case .streamCreationFailed:
            return "Could not create the file-system event stream."
        case .streamStartFailed:
            return "Could not start the file-system event stream."
        }
    }
}

@MainActor
public protocol FileEventWatching: AnyObject {
    func start(
        paths: [String],
        since eventID: UInt64?,
        onEvents: @escaping @Sendable ([FileEvent]) -> Void
    ) throws
    func stop()
}

@MainActor
public final class FSEventsWatcher: FileEventWatching {
    private var stream: FSEventStreamRef?
    private var callbackBox: CallbackBox?
    private let latency: CFTimeInterval
    private let queue: DispatchQueue

    public init(
        latency: CFTimeInterval = 0.2,
        queue: DispatchQueue = DispatchQueue(label: "com.biglol.MyMacSearch.fsevents")
    ) {
        self.latency = latency
        self.queue = queue
    }

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }

    public func start(
        paths: [String],
        since eventID: UInt64?,
        onEvents: @escaping @Sendable ([FileEvent]) -> Void
    ) throws {
        stop()
        let normalizedPaths = Array(
            Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        ).sorted()
        guard !normalizedPaths.isEmpty else { return }

        let callbackBox = CallbackBox(onEvents: onEvents)
        self.callbackBox = callbackBox
        let contextInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(callbackBox).toOpaque())
        var context = FSEventStreamContext(
            version: 0,
            info: contextInfo,
            retain: { pointer in
                guard let pointer else { return nil }
                return UnsafeRawPointer(
                    Unmanaged<CallbackBox>.fromOpaque(pointer).retain().toOpaque()
                )
            },
            release: { pointer in
                guard let pointer else { return }
                Unmanaged<CallbackBox>.fromOpaque(pointer).release()
            },
            copyDescription: nil
        )

        let startID = eventID.map { FSEventStreamEventId($0) }
            ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagNoDefer
        )

        guard let createdStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &context,
            normalizedPaths as CFArray,
            startID,
            latency,
            flags
        ) else {
            self.callbackBox = nil
            throw FSEventsWatcherError.streamCreationFailed
        }

        stream = createdStream
        FSEventStreamSetDispatchQueue(createdStream, queue)
        guard FSEventStreamStart(createdStream) else {
            stop()
            throw FSEventsWatcherError.streamStartFailed
        }
    }

    public func stop() {
        callbackBox?.deactivate()
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

    public nonisolated static func flags(
        fromRawValue rawValue: FSEventStreamEventFlags
    ) -> FileEventFlags {
        var result: FileEventFlags = []
        if rawValue & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 {
            result.insert(.created)
        }
        if rawValue & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 {
            result.insert(.removed)
        }
        if rawValue & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 {
            result.insert(.renamed)
        }
        if rawValue & FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemModified
                | kFSEventStreamEventFlagItemInodeMetaMod
                | kFSEventStreamEventFlagItemFinderInfoMod
                | kFSEventStreamEventFlagItemChangeOwner
                | kFSEventStreamEventFlagItemXattrMod
        ) != 0 {
            result.insert(.modified)
        }
        if rawValue & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0 {
            result.insert(.mustScanSubDirectories)
        }
        if rawValue & FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped) != 0 {
            result.insert(.userDropped)
        }
        if rawValue & FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped) != 0 {
            result.insert(.kernelDropped)
        }
        if rawValue & FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped) != 0 {
            result.insert(.eventIDsWrapped)
        }
        if rawValue & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
            result.insert(.rootChanged)
        }
        return result
    }

    private nonisolated static let callback: FSEventStreamCallback = {
        _, contextInfo, eventCount, eventPaths, eventFlags, eventIDs in
        guard let contextInfo else { return }
        let box = Unmanaged<CallbackBox>.fromOpaque(contextInfo).takeUnretainedValue()
        guard box.isActive else { return }
        let paths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] ?? []
        var events: [FileEvent] = []
        events.reserveCapacity(eventCount)
        for index in 0..<eventCount where index < paths.count {
            events.append(
                FileEvent(
                    path: paths[index],
                    eventID: UInt64(eventIDs[index]),
                    flags: flags(fromRawValue: eventFlags[index])
                )
            )
        }
        if !events.isEmpty {
            box.onEvents(events)
        }
    }

    private final class CallbackBox: @unchecked Sendable {
        let onEvents: @Sendable ([FileEvent]) -> Void
        private let lock = NSLock()
        private var active = true

        init(onEvents: @escaping @Sendable ([FileEvent]) -> Void) {
            self.onEvents = onEvents
        }

        var isActive: Bool {
            lock.lock()
            defer { lock.unlock() }
            return active
        }

        func deactivate() {
            lock.lock()
            active = false
            lock.unlock()
        }
    }
}
