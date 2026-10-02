import Foundation

public struct PathResolver: Sendable {
    public let aliases: [String: URL]
    private let homeDirectory: URL

    public init(
        aliases: [String: URL],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.aliases = aliases
        self.homeDirectory = homeDirectory
    }

    public func resolve(_ rawInput: String, relativeTo currentURL: URL) throws -> URL {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ExplorerError.invalidPath("")
        }

        let expanded = expandTilde(expandAlias(trimmed))
        let url: URL

        if expanded.hasPrefix("/") {
            url = URL(fileURLWithPath: expanded)
        } else {
            url = currentURL.appendingPathComponent(expanded)
        }

        return url.standardizedFileURL
    }

    private func expandTilde(_ input: String) -> String {
        if input == "~" {
            return homeDirectory.path
        }

        if input.hasPrefix("~/") {
            let suffix = String(input.dropFirst(2))
            return homeDirectory.appendingPathComponent(suffix).path
        }

        return input
    }

    private func expandAlias(_ input: String) -> String {
        let components = input.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = components.first else {
            return input
        }

        let aliasKey = String(first)
        guard let aliasURL = aliases[aliasKey] else {
            return input
        }

        if components.count == 1 {
            return aliasURL.path
        }

        return aliasURL.appendingPathComponent(String(components[1])).path
    }
}
