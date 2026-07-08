import Foundation

public enum DeletionExecutionErrorMessage {
    public static let confirmationMismatch = "confirmation phrase mismatch"
    public static let protectedPathSkipped = "protected path skipped"
    public static let pathNotFoundBeforeDelete = "path not found before delete"
}

public struct DeletionFileRemover: Sendable {
    private let trashHandler: @Sendable (URL) throws -> Void
    private let fallbackTrashHandler: (@Sendable (URL) throws -> Void)?
    private let removeHandler: @Sendable (URL) throws -> Void

    public init(
        trash: @escaping @Sendable (URL) throws -> Void,
        fallbackTrash: (@Sendable (URL) throws -> Void)? = nil,
        remove: @escaping @Sendable (URL) throws -> Void
    ) {
        self.trashHandler = trash
        self.fallbackTrashHandler = fallbackTrash
        self.removeHandler = remove
    }

    public func trash(_ url: URL) throws {
        do {
            try trashHandler(url)
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) {
                return
            }
            guard let fallbackTrashHandler else {
                throw error
            }
            do {
                try fallbackTrashHandler(url)
            } catch {
                if !FileManager.default.fileExists(atPath: url.path) {
                    return
                }
                throw error
            }
            if FileManager.default.fileExists(atPath: url.path) {
                throw error
            }
        }
    }

    public func remove(_ url: URL) throws {
        try removeHandler(url)
    }

    public static let live = DeletionFileRemover(
        trash: { url in
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        },
        fallbackTrash: { url in
            try FinderTrashFallback.moveToTrash(url)
        },
        remove: { url in
            try FileManager.default.removeItem(at: url)
        }
    )
}

private enum FinderTrashFallback {
    static func moveToTrash(_ url: URL) throws {
        let scriptSource = """
        tell application "Finder"
            delete (POSIX file \(appleScriptStringLiteral(url.path)) as alias)
        end tell
        """
        guard let script = NSAppleScript(source: scriptSource) else {
            throw FinderTrashFallbackError(message: "Finder fallback script could not be created.")
        }

        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = errorInfo["NSAppleScriptErrorMessage"] as? String
                ?? errorInfo.description
            throw FinderTrashFallbackError(message: "Finder Automation could not move item to Trash: \(message)")
        }
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private struct FinderTrashFallbackError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

public enum DeletionMode: Equatable, Sendable {
    case moveToTrash
    case permanent
}

public struct DeletionProtectionPolicy: Sendable {
    private let isProtectedHandler: @Sendable (URL) -> Bool

    public init(isProtected: @escaping @Sendable (URL) -> Bool) {
        self.isProtectedHandler = isProtected
    }

    public func isProtected(_ url: URL) -> Bool {
        isProtectedHandler(url)
    }

    public static func appCleanup(_ protectionPolicy: ProtectionPolicy = ProtectionPolicy()) -> DeletionProtectionPolicy {
        DeletionProtectionPolicy { url in
            protectionPolicy.isProtected(url)
        }
    }
}

public struct DeletionExecutor: Sendable {
    private let fileRemover: DeletionFileRemover
    private let deletionProtectionPolicy: DeletionProtectionPolicy

    public init(
        fileRemover: DeletionFileRemover = .live,
        protectionPolicy: ProtectionPolicy = ProtectionPolicy()
    ) {
        self.fileRemover = fileRemover
        self.deletionProtectionPolicy = .appCleanup(protectionPolicy)
    }

    public init(
        fileRemover: DeletionFileRemover = .live,
        deletionProtectionPolicy: DeletionProtectionPolicy
    ) {
        self.fileRemover = fileRemover
        self.deletionProtectionPolicy = deletionProtectionPolicy
    }

    public func requiredConfirmationPhrase(for app: InstalledApp) -> String {
        "DELETE"
    }

    public func execute(
        plan: DeletionPlan,
        confirmation: String,
        force: Bool = false,
        mode: DeletionMode = .moveToTrash
    ) async -> [DeletionItemResult] {
        guard confirmation == requiredConfirmationPhrase(for: plan.app) else {
            return plan.candidates.map {
                DeletionItemResult(path: $0.url.path, success: false, errorMessage: DeletionExecutionErrorMessage.confirmationMismatch)
            }
        }

        return plan.candidates.map { candidate in
            guard !candidate.isProtected, !deletionProtectionPolicy.isProtected(candidate.url) else {
                return DeletionItemResult(path: candidate.url.path, success: false, errorMessage: DeletionExecutionErrorMessage.protectedPathSkipped)
            }

            do {
                guard FileManager.default.fileExists(atPath: candidate.url.path) else {
                    return DeletionItemResult(path: candidate.url.path, success: false, errorMessage: DeletionExecutionErrorMessage.pathNotFoundBeforeDelete)
                }

                if force {
                    try prepareForForcedRemoval(at: candidate.url)
                }
                switch mode {
                case .moveToTrash:
                    try fileRemover.trash(candidate.url)
                case .permanent:
                    try fileRemover.remove(candidate.url)
                }
                return DeletionItemResult(path: candidate.url.path, success: true, errorMessage: nil)
            } catch {
                return DeletionItemResult(path: candidate.url.path, success: false, errorMessage: error.localizedDescription)
            }
        }
    }

    private func prepareForForcedRemoval(at url: URL) throws {
        if isSymbolicLink(url) {
            return
        }

        try makeWritableAndMutable(url)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }

        let contents = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )?.allObjects as? [URL] ?? []

        for child in contents.reversed() {
            if isSymbolicLink(child) {
                continue
            }
            try? makeWritableAndMutable(child)
        }
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func makeWritableAndMutable(_ url: URL) throws {
        if isSymbolicLink(url) {
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return
        }

        try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: url.path)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let currentPermissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let writablePermissions = isDirectory.boolValue ? 0o700 : 0o600
        try? FileManager.default.setAttributes(
            [.posixPermissions: currentPermissions | writablePermissions],
            ofItemAtPath: url.path
        )
    }
}
