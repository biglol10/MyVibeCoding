import AppKit
import Foundation

public enum DeletionExecutionErrorMessage {
    public static let confirmationMismatch = "confirmation phrase mismatch"
    public static let protectedPathSkipped = "protected path skipped"
    public static let pathNotFoundBeforeDelete = "path not found before delete"
}

public struct DeletionFileRemover: Sendable {
    private let trashHandler: @Sendable (URL) throws -> URL?
    private let fallbackTrashHandler: (@Sendable (URL) async throws -> URL)?
    private let removeHandler: @Sendable (URL) throws -> Void

    public init(
        trash: @escaping @Sendable (URL) throws -> Void,
        fallbackTrash: (@Sendable (URL) async throws -> URL)? = nil,
        remove: @escaping @Sendable (URL) throws -> Void
    ) {
        self.trashHandler = { url in try trash(url); return nil }
        self.fallbackTrashHandler = fallbackTrash
        self.removeHandler = remove
    }

    public init(
        recycle: @escaping @Sendable (URL) throws -> URL,
        fallbackTrash: (@Sendable (URL) async throws -> URL)? = nil,
        remove: @escaping @Sendable (URL) throws -> Void
    ) {
        self.trashHandler = { try recycle($0) }
        self.fallbackTrashHandler = fallbackTrash
        self.removeHandler = remove
    }

    @discardableResult
    public func trash(_ url: URL, allowsFallback: Bool = true) async throws -> URL? {
        do {
            let destination = try trashHandler(url)
            if let destination { try verifyMove(from: url, to: destination) }
            return destination
        } catch {
            let primaryError = error
            guard case .present = FilePresence.inspect(url), allowsFallback, let fallbackTrashHandler else {
                throw primaryError
            }
            do {
                let recycledURL = try await fallbackTrashHandler(url)
                try verifyMove(from: url, to: recycledURL)
                return recycledURL
            } catch {
                throw TrashFallbackError.bothFailed(primaryError: primaryError, fallbackError: error)
            }
        }
    }

    private func verifyMove(from source: URL, to destination: URL) throws {
        guard case .missing = FilePresence.inspect(source),
              case .present = FilePresence.inspect(destination) else {
            throw TrashFallbackError.unverifiedRecycle(sourceURL: source, recycledURL: destination)
        }
    }

    public func remove(_ url: URL) throws {
        try removeHandler(url)
    }

    public static let live = DeletionFileRemover(
        recycle: { url in
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            guard let resultingURL else { throw TrashFallbackError.missingRecycleMapping(sourceURL: url) }
            return resultingURL as URL
        },
        fallbackTrash: { url in
            try await WorkspaceTrashFallback.moveToTrash(url)
        },
        remove: { url in
            try FileManager.default.removeItem(at: url)
        }
    )
}

enum WorkspaceTrashFallback {
    static func moveToTrash(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.recycle([url]) { resultingURLs, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let recycledURL = resultingURLs.first(where: {
                    $0.key.standardizedFileURL == url.standardizedFileURL
                })?.value else {
                    continuation.resume(throwing: TrashFallbackError.missingRecycleMapping(sourceURL: url))
                    return
                }
                continuation.resume(returning: recycledURL)
            }
        }
    }
}

private enum TrashFallbackError: LocalizedError {
    case missingRecycleMapping(sourceURL: URL)
    case unverifiedRecycle(sourceURL: URL, recycledURL: URL)
    case bothFailed(primaryError: Error, fallbackError: Error)

    var errorDescription: String? {
        switch self {
        case let .missingRecycleMapping(sourceURL):
            "App bundle Trash fallback completed without a recycle mapping for \(sourceURL.path)."
        case let .unverifiedRecycle(sourceURL, recycledURL):
            "App bundle Trash fallback could not verify that \(sourceURL.path) moved to \(recycledURL.path)."
        case let .bothFailed(primaryError, fallbackError):
            "Standard Trash failed: \(primaryError.localizedDescription). App bundle Trash fallback failed: \(fallbackError.localizedDescription)"
        }
    }
}

public enum DeletionMode: String, Codable, Equatable, Sendable {
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
        mode: DeletionMode = .moveToTrash,
        requiredConfirmation: String = "DELETE"
    ) async -> [DeletionItemResult] {
        guard confirmation == requiredConfirmation else {
            return plan.candidates.map {
                DeletionItemResult(path: $0.url.path, success: false, errorMessage: DeletionExecutionErrorMessage.confirmationMismatch)
            }
        }

        var results: [DeletionItemResult] = []
        for candidate in plan.candidates {
            guard !candidate.isProtected, !deletionProtectionPolicy.isProtected(candidate.url) else {
                results.append(DeletionItemResult(path: candidate.url.path, success: false, errorMessage: DeletionExecutionErrorMessage.protectedPathSkipped))
                continue
            }

            do {
                switch FilePresence.inspect(candidate.url) {
                case .missing:
                    results.append(DeletionItemResult(path: candidate.url.path, success: false, errorMessage: DeletionExecutionErrorMessage.pathNotFoundBeforeDelete))
                    continue
                case .unavailable(let code):
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
                case .present:
                    break
                }

                if force {
                    try prepareForForcedRemoval(at: candidate.url)
                }
                let trashURL: URL?
                switch mode {
                case .moveToTrash:
                    trashURL = try await fileRemover.trash(candidate.url, allowsFallback: allowsTrashFallback(for: candidate))
                case .permanent:
                    try fileRemover.remove(candidate.url)
                    trashURL = nil
                }
                results.append(DeletionItemResult(path: candidate.url.path, success: true, errorMessage: nil, trashPath: trashURL?.path))
            } catch {
                let permissionDenied: Bool
                if case let TrashFallbackError.bothFailed(primary, fallback) = error {
                    permissionDenied = FilePermissionFailure.matches(primary) || FilePermissionFailure.matches(fallback)
                } else {
                    permissionDenied = FilePermissionFailure.matches(error)
                }
                results.append(DeletionItemResult(path: candidate.url.path, success: false, errorMessage: error.localizedDescription, permissionDenied: permissionDenied))
            }
        }
        return results
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

    private func allowsTrashFallback(for candidate: RelatedFileCandidate) -> Bool {
        candidate.kind == .appBundle && candidate.url.pathExtension.lowercased() == "app"
    }
}
