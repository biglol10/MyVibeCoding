import Foundation

public enum ExplorerSessionStoreError: LocalizedError, Equatable, Sendable {
    case payloadTooLarge(maximumBytes: Int)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge(let maximumBytes):
            return "Saved session exceeds the \(maximumBytes)-byte safety limit."
        case .unsupportedVersion(let version):
            return "Saved session version \(version) is not supported."
        }
    }
}

public protocol ExplorerSessionStoring: AnyObject {
    func load() throws -> ExplorerSessionSnapshot?
    func save(_ snapshot: ExplorerSessionSnapshot) throws
    func reset() throws
}

public extension ExplorerSessionStoring {
    func reset() throws {}
}

public final class TransientExplorerSessionStore: ExplorerSessionStoring {
    private var snapshot: ExplorerSessionSnapshot?

    public init() {}

    public func load() throws -> ExplorerSessionSnapshot? {
        snapshot
    }

    public func save(_ snapshot: ExplorerSessionSnapshot) throws {
        self.snapshot = snapshot
    }

    public func reset() throws {
        snapshot = nil
    }
}

public final class UserDefaultsExplorerSessionStore: ExplorerSessionStoring {
    private let defaults: UserDefaults
    private let key: String
    private let maximumPayloadBytes: Int

    public init(
        defaults: UserDefaults = .standard,
        key: String = "MyMacFinder.ExplorerSession",
        maximumPayloadBytes: Int = 1_048_576
    ) {
        self.defaults = defaults
        self.key = key
        self.maximumPayloadBytes = maximumPayloadBytes
    }

    public func load() throws -> ExplorerSessionSnapshot? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        guard data.count <= maximumPayloadBytes else {
            throw ExplorerSessionStoreError.payloadTooLarge(maximumBytes: maximumPayloadBytes)
        }
        let snapshot = try JSONDecoder().decode(ExplorerSessionSnapshot.self, from: data)
        guard snapshot.version == ExplorerSessionSnapshot.currentVersion else {
            throw ExplorerSessionStoreError.unsupportedVersion(snapshot.version)
        }
        return snapshot
    }

    public func save(_ snapshot: ExplorerSessionSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= maximumPayloadBytes else {
            throw ExplorerSessionStoreError.payloadTooLarge(maximumBytes: maximumPayloadBytes)
        }
        defaults.set(data, forKey: key)
    }

    public func reset() throws {
        defaults.removeObject(forKey: key)
    }
}
