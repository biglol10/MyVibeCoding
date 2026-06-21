import Foundation

public struct InstalledApp: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let displayName: String
    public let bundleIdentifier: String?
    public let version: String?
    public let executableName: String?
    public let bundleURL: URL
    public let iconIdentifier: String?
    public let bundleSize: Int64
    public let lastOpenedAt: Date?

    public init(
        id: UUID = UUID(),
        displayName: String,
        bundleIdentifier: String?,
        version: String?,
        executableName: String?,
        bundleURL: URL,
        iconIdentifier: String?,
        bundleSize: Int64,
        lastOpenedAt: Date?
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.executableName = executableName
        self.bundleURL = bundleURL
        self.iconIdentifier = iconIdentifier
        self.bundleSize = bundleSize
        self.lastOpenedAt = lastOpenedAt
    }
}
