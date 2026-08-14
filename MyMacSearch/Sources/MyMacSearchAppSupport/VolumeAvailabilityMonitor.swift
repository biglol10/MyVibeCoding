import AppKit
import Foundation

public enum VolumeAvailability: Equatable, Sendable {
    case available
    case offline
    case identityMismatch(actualUUID: String?)
}

public struct VolumeResource: Equatable, Sendable {
    public let isReachable: Bool
    public let volumeUUID: String?

    public init(isReachable: Bool, volumeUUID: String?) {
        self.isReachable = isReachable
        self.volumeUUID = volumeUUID
    }
}

public protocol VolumeResourceReading: Sendable {
    func resource(for rootPath: String) -> VolumeResource
}

public struct FoundationVolumeResourceReader: VolumeResourceReading {
    public init() {}

    public func resource(for rootPath: String) -> VolumeResource {
        let url = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return VolumeResource(isReachable: false, volumeUUID: nil)
        }
        let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey])
        return VolumeResource(isReachable: true, volumeUUID: values?.volumeUUIDString)
    }
}

public actor VolumeAvailabilityChecker<Client: VolumeResourceReading> {
    private let client: Client

    public init(client: Client) {
        self.client = client
    }

    public func availability(rootPath: String, expectedVolumeUUID: String?) -> VolumeAvailability {
        let resource = client.resource(for: rootPath)
        guard resource.isReachable else { return .offline }
        guard let expectedVolumeUUID else {
            return .identityMismatch(actualUUID: resource.volumeUUID)
        }
        guard resource.volumeUUID == expectedVolumeUUID else {
            return .identityMismatch(actualUUID: resource.volumeUUID)
        }
        return .available
    }
}

public struct MonitoredVolumeScope: Equatable, Sendable {
    public let id: String
    public let rootPath: String
    public let expectedVolumeUUID: String?

    public init(id: String, rootPath: String, expectedVolumeUUID: String?) {
        self.id = id
        self.rootPath = rootPath
        self.expectedVolumeUUID = expectedVolumeUUID
    }
}

@MainActor
public final class VolumeAvailabilityMonitor {
    public typealias Handler = @MainActor (String, VolumeAvailability) -> Void

    private let checker = VolumeAvailabilityChecker(client: FoundationVolumeResourceReader())
    private var scopes: [MonitoredVolumeScope] = []
    private var observers: [NotificationObservation] = []
    private var handler: Handler?
    private var refreshTask: Task<Void, Never>?

    public init() {}

    deinit {
        refreshTask?.cancel()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer.token)
        }
    }

    public func start(scopes: [MonitoredVolumeScope], handler: @escaping Handler) {
        stop()
        self.scopes = scopes
        self.handler = handler
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            }
            observers.append(NotificationObservation(token))
        }
        scheduleRefresh()
    }

    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0.token) }
        observers.removeAll()
        scopes.removeAll()
        handler = nil
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        let scopes = scopes
        let checker = checker
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self else { return }
            for scope in scopes {
                let availability = await checker.availability(
                    rootPath: scope.rootPath,
                    expectedVolumeUUID: scope.expectedVolumeUUID
                )
                self.handler?(scope.id, availability)
            }
        }
    }
}

private final class NotificationObservation: @unchecked Sendable {
    let token: NSObjectProtocol

    init(_ token: NSObjectProtocol) {
        self.token = token
    }
}
