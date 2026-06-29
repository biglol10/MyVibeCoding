import Foundation

public struct ArchiveLocation: Codable, Equatable, Hashable, Sendable {
    public var archiveURL: URL
    public var internalPath: String

    public init(archiveURL: URL, internalPath: String) {
        self.archiveURL = archiveURL.standardizedFileURL
        self.internalPath = Self.normalize(internalPath)
    }

    public var displayPath: String {
        internalPath.isEmpty ? "\(archiveURL.path)/" : "\(archiveURL.path)/\(internalPath)"
    }

    public var virtualURL: URL {
        let archiveKey = archiveURL.path
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? String(abs(archiveURL.path.hashValue))
        let entryKey = internalPath.isEmpty ? "__root__" : internalPath
        return URL(fileURLWithPath: "/__MyMacFinderArchive__")
            .appendingPathComponent(archiveKey, isDirectory: true)
            .appendingPathComponent(entryKey)
    }

    public var parent: ArchiveLocation {
        guard !internalPath.isEmpty else {
            return self
        }
        let parentPath = NSString(string: internalPath).deletingLastPathComponent
        return ArchiveLocation(archiveURL: archiveURL, internalPath: parentPath == "." ? "" : parentPath)
    }

    public func appending(_ component: String) -> ArchiveLocation {
        ArchiveLocation(
            archiveURL: archiveURL,
            internalPath: [internalPath, component].filter { !$0.isEmpty }.joined(separator: "/")
        )
    }

    public static func normalize(_ rawPath: String) -> String {
        rawPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
    }
}

public enum PaneLocation: Codable, Equatable, Hashable, Sendable {
    case fileSystem(URL)
    case archive(ArchiveLocation)

    public var displayPath: String {
        switch self {
        case .fileSystem(let url):
            return url.path
        case .archive(let location):
            return location.displayPath
        }
    }

    public var fileSystemURL: URL? {
        switch self {
        case .fileSystem(let url):
            return url
        case .archive:
            return nil
        }
    }

    public var archiveLocation: ArchiveLocation? {
        switch self {
        case .fileSystem:
            return nil
        case .archive(let location):
            return location
        }
    }

    public var isArchive: Bool {
        archiveLocation != nil
    }
}

public enum FileEntrySource: Codable, Equatable, Hashable, Sendable {
    case fileSystem
    case archive(ArchiveLocation)
}
