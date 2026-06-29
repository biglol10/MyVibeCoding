import Foundation
import ZIPFoundation

public struct ArchiveEntry: Equatable, Sendable {
    public var location: ArchiveLocation
    public var name: String
    public var isDirectory: Bool
    public var size: Int64?
    public var modifiedAt: Date?

    public init(
        location: ArchiveLocation,
        name: String,
        isDirectory: Bool,
        size: Int64?,
        modifiedAt: Date?
    ) {
        self.location = location
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

public protocol ArchiveBrowsing: Sendable {
    func canOpen(_ url: URL) -> Bool
    func list(_ location: ArchiveLocation, showHiddenFiles: Bool) async throws -> [ArchiveEntry]
    func temporaryExtract(_ location: ArchiveLocation) async throws -> URL
}

public struct ArchiveBrowsingService: ArchiveBrowsing, @unchecked Sendable {
    private let fileManager: FileManager
    private let extractionRoot: URL

    public init(
        fileManager: FileManager = .default,
        extractionRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyMacFinderArchivePreview", isDirectory: true)
    ) {
        self.fileManager = fileManager
        self.extractionRoot = extractionRoot
    }

    public func canOpen(_ url: URL) -> Bool {
        url.pathExtension.localizedCaseInsensitiveCompare("zip") == .orderedSame
    }

    public func list(_ location: ArchiveLocation, showHiddenFiles: Bool) async throws -> [ArchiveEntry] {
        try await Task.detached(priority: .userInitiated) {
            let archive = try self.openArchive(location.archiveURL)
            let prefix = location.internalPath.isEmpty ? "" : "\(location.internalPath)/"
            var folders: [String: ArchiveEntry] = [:]
            var files: [ArchiveEntry] = []

            for entry in archive {
                guard entry.path.hasPrefix(prefix) else {
                    continue
                }

                let remainder = String(entry.path.dropFirst(prefix.count))
                guard !remainder.isEmpty else {
                    continue
                }

                let components = remainder.split(separator: "/", omittingEmptySubsequences: true)
                guard let first = components.first else {
                    continue
                }

                let name = String(first)
                if !showHiddenFiles && name.hasPrefix(".") {
                    continue
                }

                if components.count > 1 {
                    let folderLocation = location.appending(name)
                    folders[name] = ArchiveEntry(
                        location: folderLocation,
                        name: name,
                        isDirectory: true,
                        size: nil,
                        modifiedAt: nil
                    )
                    continue
                }

                let entryLocation = location.appending(name)
                if entry.type == .directory {
                    folders[name] = ArchiveEntry(
                        location: entryLocation,
                        name: name,
                        isDirectory: true,
                        size: nil,
                        modifiedAt: entry.fileAttributes[.modificationDate] as? Date
                    )
                } else {
                    files.append(
                        ArchiveEntry(
                            location: entryLocation,
                            name: name,
                            isDirectory: false,
                            size: Int64(entry.uncompressedSize),
                            modifiedAt: entry.fileAttributes[.modificationDate] as? Date
                        )
                    )
                }
            }

            return Array(folders.values) + files
        }.value
    }

    public func temporaryExtract(_ location: ArchiveLocation) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let archive = try self.openArchive(location.archiveURL)
            guard let entry = archive[location.internalPath], entry.type != .directory else {
                throw ExplorerError.readFailed("ZIP entry cannot be previewed: \(location.displayPath)")
            }

            try self.fileManager.createDirectory(at: self.extractionRoot, withIntermediateDirectories: true)
            let targetFolder = self.extractionRoot
                .appendingPathComponent(location.archiveURL.deletingPathExtension().lastPathComponent, isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try self.fileManager.createDirectory(at: targetFolder, withIntermediateDirectories: true)
            let destination = targetFolder.appendingPathComponent(URL(fileURLWithPath: location.internalPath).lastPathComponent)
            _ = try archive.extract(entry, to: destination)
            return destination
        }.value
    }

    private func openArchive(_ url: URL) throws -> Archive {
        do {
            return try Archive(url: url, accessMode: .read)
        } catch {
            throw ExplorerError.readFailed("ZIP archive could not be read: \(url.path)")
        }
    }
}
