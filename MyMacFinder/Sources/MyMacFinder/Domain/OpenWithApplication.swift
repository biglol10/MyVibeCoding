import Foundation

public struct OpenWithApplication: Hashable, Identifiable, Sendable {
    public let url: URL
    public let title: String
    public let bundleIdentifier: String?

    public var id: URL {
        url.standardizedFileURL
    }

    public init(url: URL, title: String, bundleIdentifier: String?) {
        self.url = url.standardizedFileURL
        self.title = title
        self.bundleIdentifier = bundleIdentifier
    }
}
