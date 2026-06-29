import Foundation
import UniformTypeIdentifiers

public struct DirectoryReadOptions: Sendable {
    public var showHiddenFiles: Bool
    public var includeFinderTags: Bool

    public init(showHiddenFiles: Bool = false, includeFinderTags: Bool = false) {
        self.showHiddenFiles = showHiddenFiles
        self.includeFinderTags = includeFinderTags
    }
}

public protocol FileSystemServicing: Sendable {
    func contentsOfDirectory(at url: URL, options: DirectoryReadOptions) async throws -> [FileEntry]
}

public struct FileSystemService: FileSystemServicing, @unchecked Sendable {
    private let fileManager: FileManager
    private let finderTagService: any FinderTagServicing

    public init(
        fileManager: FileManager = .default,
        finderTagService: any FinderTagServicing = FinderTagService()
    ) {
        self.fileManager = fileManager
        self.finderTagService = finderTagService
    }

    public func contentsOfDirectory(at url: URL, options: DirectoryReadOptions = DirectoryReadOptions()) async throws -> [FileEntry] {
        try validateDirectory(url)
        let readURL = directoryReadURL(for: url)

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .isHiddenKey,
            .isReadableKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .contentAccessDateKey,
            .typeIdentifierKey,
            .localizedTypeDescriptionKey
        ]

        let childURLs = try fileManager.contentsOfDirectory(
            at: readURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsSubdirectoryDescendants]
        )

        return try childURLs.compactMap { childURL in
            let displayURL = displayURL(for: childURL, readRootURL: readURL, displayRootURL: url)
            let entry = try makeEntry(
                for: childURL,
                displayURL: displayURL,
                resourceKeys: keys,
                includeFinderTags: options.includeFinderTags
            )
            if !options.showHiddenFiles && entry.isHidden {
                return nil
            }
            return entry
        }
    }

    private func directoryReadURL(for url: URL) -> URL {
        guard (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else {
            return url
        }
        return url.resolvingSymlinksInPath()
    }

    private func displayURL(for childURL: URL, readRootURL: URL, displayRootURL: URL) -> URL {
        guard readRootURL.standardizedFileURL != displayRootURL.standardizedFileURL else {
            return childURL
        }
        return displayRootURL.appendingPathComponent(childURL.lastPathComponent)
    }

    private func validateDirectory(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ExplorerError.pathDoesNotExist(url.path)
        }
        guard isDirectory.boolValue else {
            throw ExplorerError.notDirectory(url.path)
        }
        guard fileManager.isReadableFile(atPath: url.path) else {
            throw ExplorerError.permissionDenied(url.path)
        }
    }

    private func makeEntry(
        for url: URL,
        displayURL: URL? = nil,
        resourceKeys: Set<URLResourceKey>,
        includeFinderTags: Bool
    ) throws -> FileEntry {
        let values = try url.resourceValues(forKeys: resourceKeys)
        let displayURL = displayURL ?? url
        let name = displayURL.lastPathComponent
        let isDirectory = values.isDirectory == true
        let isPackage = values.isPackage == true
        let isSymlink = values.isSymbolicLink == true
        let isDirectoryLike = (isDirectory && !isPackage) || (isSymlink && symlinkTargetIsDirectory(url))
        let hiddenByName = name.hasPrefix(".")
        let hiddenByFlag = values.isHidden == true
        let kind = determineKind(url: displayURL, isDirectory: isDirectory, isPackage: isPackage, isSymlink: isSymlink)
        let finderTags = includeFinderTags ? ((try? finderTagService.tags(for: displayURL)) ?? []) : []

        return FileEntry(
            url: displayURL.standardizedFileURL,
            name: name,
            kind: kind,
            typeDescription: values.localizedTypeDescription ?? fallbackTypeDescription(kind: kind, extension: displayURL.pathExtension),
            fileExtension: displayURL.pathExtension.lowercased(),
            size: values.fileSize.map(Int64.init),
            dateModified: values.contentModificationDate,
            dateCreated: values.creationDate,
            dateAccessed: values.contentAccessDate,
            isHidden: hiddenByName || hiddenByFlag,
            isDirectoryLike: isDirectoryLike,
            isReadable: values.isReadable ?? FileManager.default.isReadableFile(atPath: url.path),
            finderTags: finderTags
        )
    }

    private func symlinkTargetIsDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.resolvingSymlinksInPath().path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func determineKind(url: URL, isDirectory: Bool, isPackage: Bool, isSymlink: Bool) -> FileEntryKind {
        if isSymlink {
            return .symlink
        }
        if isPackage {
            return .package
        }
        if isDirectory {
            return .folder
        }
        if url.pathExtension.lowercased() == "zip" {
            return .zipVirtualFolder
        }
        return .file
    }

    private func fallbackTypeDescription(kind: FileEntryKind, extension fileExtension: String) -> String {
        switch kind {
        case .folder:
            return "Folder"
        case .symlink:
            return "Alias"
        case .package:
            return "Package"
        case .zipVirtualFolder:
            return "ZIP Archive"
        case .file:
            return fileExtension.isEmpty ? "File" : "\(fileExtension.uppercased()) File"
        case .volume:
            return "Volume"
        case .zipVirtualFile:
            return "ZIP Item"
        case .other:
            return "Item"
        }
    }
}
