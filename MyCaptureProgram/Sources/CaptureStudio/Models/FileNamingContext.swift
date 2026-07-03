import Foundation

public struct FileNamingContext: Codable, Equatable, Sendable {
    public var applicationName: String
    public var windowTitle: String?

    public init(applicationName: String, windowTitle: String? = nil) {
        self.applicationName = applicationName
        self.windowTitle = windowTitle
    }

    public var displayTitle: String {
        [applicationName, windowTitle ?? ""]
            .compactMap { value -> String? in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " - ")
    }
}
