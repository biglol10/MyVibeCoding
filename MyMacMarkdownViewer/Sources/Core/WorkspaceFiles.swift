import Foundation

public enum WorkspaceFileError: LocalizedError, Equatable, Sendable {
    case invalidName
    case unsafePath
    case rootProtected
    case notFound
    case notDirectory
    case alreadyExists
    case invalidMove
    case renameFailed
    case renameRecoveryRequired(URL)
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .invalidName: "파일 또는 폴더 이름을 확인해 주세요. 빈 이름, . , .., /, NUL 문자는 사용할 수 없습니다."
        case .unsafePath: "작업 폴더 밖이거나 심볼릭 링크를 지나는 경로에는 접근할 수 없습니다."
        case .rootProtected: "작업 폴더 자체는 이동하거나 휴지통으로 보낼 수 없습니다."
        case .notFound: "대상 파일 또는 폴더를 찾을 수 없습니다."
        case .notDirectory: "대상 위치는 실제 폴더여야 합니다."
        case .alreadyExists: "같은 이름의 파일 또는 폴더가 이미 있습니다."
        case .invalidMove: "폴더를 자기 자신 또는 그 안으로 옮길 수 없습니다."
        case .renameFailed: "대소문자만 바꾸는 이름 변경을 완료하지 못했습니다. 원래 이름으로 되돌렸습니다."
        case .renameRecoveryRequired(let temporaryURL): "이름 변경을 되돌리지 못했습니다. 파일은 \(temporaryURL.path)에 남아 있습니다."
        case .unavailable: "파일 작업을 완료할 수 없습니다. 접근 권한과 동기화 상태를 확인해 주세요."
        }
    }
}

/// Native, workspace-bounded file operations for the document sidebar.
public actor WorkspaceFiles {
    private let fileManager: FileManager
    private let moveItem: @Sendable (URL, URL) throws -> Void

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        moveItem = { source, destination in try FileManager.default.moveItem(at: source, to: destination) }
    }

    init(fileManager: FileManager, moveItem: @escaping @Sendable (URL, URL) throws -> Void) {
        self.fileManager = fileManager
        self.moveItem = moveItem
    }

    public func createDocument(root: URL, directory: URL, name: String) throws -> URL {
        let safeRoot = try validateRoot(root)
        let safeDirectory = try validateExisting(directory, within: safeRoot, directory: true)
        let filename = try documentName(from: name)
        let target = safeDirectory.appendingPathComponent(filename)
        try validateNewTarget(target, within: safeRoot)
        try coordinateWrite(at: target) { coordinatedTarget in
            try self.ensureNoCollision(at: coordinatedTarget)
            try Data().write(to: coordinatedTarget, options: .withoutOverwriting)
        }
        return target
    }

    public func createFolder(root: URL, directory: URL, name: String) throws -> URL {
        let safeRoot = try validateRoot(root)
        let safeDirectory = try validateExisting(directory, within: safeRoot, directory: true)
        let filename = try validName(name)
        let target = safeDirectory.appendingPathComponent(filename)
        try validateNewTarget(target, within: safeRoot)
        try coordinateWrite(at: target) { coordinatedTarget in
            try self.ensureNoCollision(at: coordinatedTarget)
            try self.fileManager.createDirectory(at: coordinatedTarget, withIntermediateDirectories: false)
        }
        return target
    }

    /// Creates a sibling copy without replacing any existing item. Links are copied as links.
    public func duplicate(root: URL, source: URL) throws -> URL {
        let safeRoot = try validateRoot(root)
        let source = try validateExisting(source, within: safeRoot)
        guard source != safeRoot else { throw WorkspaceFileError.rootProtected }
        let directory = try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        let ext = directory ? "" : source.pathExtension
        let base = ext.isEmpty ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        let parent = source.deletingLastPathComponent()
        var number = 1
        var target: URL
        while true {
            let suffix = number == 1 ? " 복사본" : " 복사본 \(number)"
            target = parent.appendingPathComponent(base + suffix + (ext.isEmpty ? "" : "." + ext))
            do { try ensureNoCollision(at: target); break }
            catch WorkspaceFileError.alreadyExists { number += 1 }
        }
        try validateNewTarget(target, within: safeRoot)
        var coordinationError: NSError?
        var outcome: Result<Void, Error> = .failure(WorkspaceFileError.unavailable)
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], writingItemAt: target, options: [], error: &coordinationError) { from, to in
            outcome = Result {
                _ = try self.validateExisting(from, within: safeRoot)
                try self.ensureNoCollision(at: to)
                let staging = to.deletingLastPathComponent().appendingPathComponent(".mymarkdown-copy-" + UUID().uuidString)
                defer { try? self.fileManager.removeItem(at: staging) }
                try self.fileManager.copyItem(at: from, to: staging)
                try self.ensureNoCollision(at: to)
                try self.fileManager.moveItem(at: staging, to: to)
            }
        }
        if let coordinationError { throw coordinationError }
        try outcome.get()
        return target
    }

    /// Moves `source` to the exact final `destination`, which may give it a new name.
    public func move(root: URL, source: URL, destination: URL) throws -> URL {
        let safeRoot = try validateRoot(root)
        let safeSource = try validateExisting(source, within: safeRoot)
        guard safeSource != safeRoot else { throw WorkspaceFileError.rootProtected }
        let sourceValues = try safeSource.resourceValues(forKeys: [.isDirectoryKey])
        try ensureNoDotComponents(destination)
        let normalizedDestination = destination.standardizedFileURL
        guard isSameOrDescendant(normalizedDestination, of: safeRoot) else { throw WorkspaceFileError.unsafePath }
        let destinationName = try validName(normalizedDestination.lastPathComponent)
        let requestedDestination = normalizedDestination.deletingLastPathComponent().appendingPathComponent(destinationName)
        if sourceValues.isDirectory == true, isSameOrDescendant(requestedDestination, of: safeSource) {
            throw WorkspaceFileError.invalidMove
        }
        let destinationParent = try validateExisting(requestedDestination.deletingLastPathComponent(), within: safeRoot, directory: true)
        let safeDestination = destinationParent.appendingPathComponent(destinationName)
        try validateNewTarget(safeDestination, within: safeRoot)
        if sourceValues.isDirectory == true, isSameOrDescendant(safeDestination, of: safeSource) {
            throw WorkspaceFileError.invalidMove
        }

        try coordinateMove(from: safeSource, to: safeDestination) { coordinatedSource, coordinatedDestination in
            try self.ensureMoveDestinationIsAvailable(source: coordinatedSource, destination: coordinatedDestination)
            if self.isCaseOnlyRename(from: coordinatedSource, to: coordinatedDestination) {
                let temporary = coordinatedSource.deletingLastPathComponent()
                    .appendingPathComponent(".mymarkdown-rename-\(UUID().uuidString)")
                try self.moveItem(coordinatedSource, temporary)
                do {
                    try self.moveItem(temporary, coordinatedDestination)
                } catch {
                    do {
                        try self.moveItem(temporary, coordinatedSource)
                    } catch {
                        throw WorkspaceFileError.renameRecoveryRequired(temporary)
                    }
                    throw WorkspaceFileError.renameFailed
                }
            } else {
                try self.moveItem(coordinatedSource, coordinatedDestination)
            }
        }
        return safeDestination
    }

    /// Sends an item to the user's Trash. The returned URL is the system-selected Trash location when available.
    public func trash(root: URL, source: URL) throws -> URL? {
        let safeRoot = try validateRoot(root)
        let safeSource = try validateExisting(source, within: safeRoot)
        guard safeSource != safeRoot else { throw WorkspaceFileError.rootProtected }
        var trashedURL: URL?
        try coordinateWrite(at: safeSource) { coordinatedSource in
            var result: NSURL?
            try self.fileManager.trashItem(at: coordinatedSource, resultingItemURL: &result)
            trashedURL = result as URL?
        }
        return trashedURL
    }

    /// Returns every Markdown document affected by relocating `source` before any move occurs.
    /// Hidden Markdown files are included; symlinks and package contents are excluded.
    public func markdownDocuments(root: URL, source: URL) throws -> [URL] {
        let safeRoot = try validateRoot(root)
        let safeSource = try validateExisting(source, within: safeRoot)
        let sourceValues = try safeSource.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if sourceValues.isDirectory != true {
            guard sourceValues.isRegularFile == true, MarkdownFileSupport.isMarkdownFile(safeSource) else {
                throw WorkspaceFileError.unavailable
            }
            guard fileManager.isReadableFile(atPath: safeSource.path) else { throw WorkspaceFileError.unavailable }
            return [safeSource]
        }

        var enumerationFailed = false
        guard let enumerator = fileManager.enumerator(
            at: safeSource,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in enumerationFailed = true; return false }
        ) else { throw WorkspaceFileError.unavailable }

        var documents: [URL] = []
        for case let url as URL in enumerator {
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey])
            } catch {
                throw WorkspaceFileError.unavailable
            }
            if values.isSymbolicLink == true || values.isPackage == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            guard values.isDirectory != true, values.isRegularFile == true, MarkdownFileSupport.isMarkdownFile(url) else { continue }
            guard fileManager.isReadableFile(atPath: url.path) else { throw WorkspaceFileError.unavailable }
            documents.append(url.standardizedFileURL)
        }
        if enumerationFailed { throw WorkspaceFileError.unavailable }
        return documents.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func validateRoot(_ root: URL) throws -> URL {
        let normalized = root.standardizedFileURL
        try ensureNoDotComponents(root)
        try ensureNoSymlinkComponents(from: normalized, through: normalized)
        let values = try normalized.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw WorkspaceFileError.notDirectory }
        return normalized
    }

    private func validateExisting(_ url: URL, within root: URL, directory: Bool? = nil) throws -> URL {
        try ensureNoDotComponents(url)
        let normalized = url.standardizedFileURL
        guard isSameOrDescendant(normalized, of: root) else { throw WorkspaceFileError.unsafePath }
        try ensureNoSymlinkComponents(from: root, through: normalized)
        guard fileManager.fileExists(atPath: normalized.path) else { throw WorkspaceFileError.notFound }
        if let directory {
            let values = try normalized.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == directory else { throw directory ? WorkspaceFileError.notDirectory : WorkspaceFileError.unavailable }
        }
        return normalized
    }

    private func validateNewTarget(_ url: URL, within root: URL) throws {
        try ensureNoDotComponents(url)
        let normalized = url.standardizedFileURL
        guard isSameOrDescendant(normalized, of: root), normalized != root else { throw WorkspaceFileError.unsafePath }
        try ensureNoSymlinkComponents(from: root, through: normalized.deletingLastPathComponent())
    }

    private func ensureNoDotComponents(_ url: URL) throws {
        let path = url.path
        guard !path.hasSuffix("/.."), !path.contains("/../"), !path.hasSuffix("/.") , !path.contains("/./") else {
            throw WorkspaceFileError.unsafePath
        }
    }

    private func ensureNoSymlinkComponents(from root: URL, through target: URL) throws {
        guard isSameOrDescendant(target, of: root) else { throw WorkspaceFileError.unsafePath }
        var current = root
        try ensureNotSymlink(current)
        let rootComponents = root.pathComponents
        for component in target.pathComponents.dropFirst(rootComponents.count) {
            current.appendPathComponent(component)
            if fileManager.fileExists(atPath: current.path) {
                try ensureNotSymlink(current)
            }
        }
    }

    private func ensureNotSymlink(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values.isSymbolicLink == true { throw WorkspaceFileError.unsafePath }
    }

    private func validName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != "..", !name.contains("/"), !name.utf8.contains(0) else {
            throw WorkspaceFileError.invalidName
        }
        return name
    }

    private func documentName(from name: String) throws -> String {
        let filename = try validName(name)
        return MarkdownFileSupport.isMarkdownFile(URL(fileURLWithPath: filename)) ? filename : filename + ".md"
    }

    private func ensureNoCollision(at target: URL) throws {
        let parent = target.deletingLastPathComponent()
        let desiredName = target.lastPathComponent
        let names = try fileManager.contentsOfDirectory(atPath: parent.path)
        guard !names.contains(where: { $0.caseInsensitiveCompare(desiredName) == .orderedSame }) else {
            throw WorkspaceFileError.alreadyExists
        }
    }

    private func ensureMoveDestinationIsAvailable(source: URL, destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        let desiredName = destination.lastPathComponent
        let sourceIsInParent = source.deletingLastPathComponent() == parent
        let names = try fileManager.contentsOfDirectory(atPath: parent.path)
        for name in names where name.caseInsensitiveCompare(desiredName) == .orderedSame {
            if sourceIsInParent && name == source.lastPathComponent { continue }
            throw WorkspaceFileError.alreadyExists
        }
    }

    private func isCaseOnlyRename(from source: URL, to destination: URL) -> Bool {
        source.deletingLastPathComponent() == destination.deletingLastPathComponent()
            && source.lastPathComponent != destination.lastPathComponent
            && source.lastPathComponent.caseInsensitiveCompare(destination.lastPathComponent) == .orderedSame
    }

    private func isSameOrDescendant(_ url: URL, of root: URL) -> Bool {
        let urlComponents = url.pathComponents
        let rootComponents = root.pathComponents
        return urlComponents.count >= rootComponents.count && zip(urlComponents, rootComponents).allSatisfy(==)
    }

    private func coordinateWrite(at url: URL, operation: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var outcome: Result<Void, Error> = .failure(WorkspaceFileError.unavailable)
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            outcome = Result { try operation(coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        try outcome.get()
    }

    private func coordinateMove(from source: URL, to destination: URL, operation: (URL, URL) throws -> Void) throws {
        var coordinationError: NSError?
        var outcome: Result<Void, Error> = .failure(WorkspaceFileError.unavailable)
        NSFileCoordinator().coordinate(writingItemAt: source, options: .forMoving, writingItemAt: destination, options: .forReplacing, error: &coordinationError) { coordinatedSource, coordinatedDestination in
            outcome = Result { try operation(coordinatedSource, coordinatedDestination) }
        }
        if let coordinationError { throw coordinationError }
        try outcome.get()
    }
}
