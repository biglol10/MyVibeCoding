import Darwin
import Foundation

public struct BatchRenameRule: Equatable, Sendable {
    public var find = ""
    public var replacement = ""
    public var prefix = ""
    public var suffix = ""
    public var numbered = false
    public var start = 1
    public init() {}
    public func name(for entry: FileEntry, index: Int) -> String {
        let ext = entry.isDirectoryLike ? "" : entry.url.pathExtension
        let base = ext.isEmpty ? entry.name : String(entry.name.dropLast(ext.count + 1))
        let changed = find.isEmpty ? base : base.replacingOccurrences(of: find, with: replacement)
        let number = numbered ? String(start + index) : ""
        return prefix + changed + suffix + number + (ext.isEmpty ? "" : "." + ext)
    }
}

public struct BatchRenamePlan: Identifiable, Equatable, Sendable {
    public var id: URL { source }
    public let source: URL
    public let destination: URL
    let identity: FileSystemPathIdentity.FileSystemEntryIdentity
}

public struct BatchRenameOutcome: Sendable {
    public let result: FileOperationResult
    public let errorMessage: String?
}

public struct BatchRenameService: Sendable {
    private let move: @Sendable (URL, URL) throws -> Void
    public init(move: @escaping @Sendable (URL, URL) throws -> Void = BatchRenameService.exclusiveMove) { self.move = move }
    public static func plan(entries: [FileEntry], rule: BatchRenameRule) throws -> [BatchRenamePlan] {
        guard !entries.isEmpty, rule.start >= 0, rule.start <= Int.max - entries.count else {
            throw ExplorerError.operationFailed("Choose files and a valid starting number.")
        }
        var destinations = Set<String>()
        let originals = entries.map { $0.url.standardizedFileURL.path }
        var plans: [BatchRenamePlan] = []
        for (index, entry) in entries.enumerated() {
            guard !entry.isArchiveBacked, let identity = FileSystemPathIdentity.entryIdentity(entry.url) else {
                throw ExplorerError.operationFailed("An item is unavailable: \(entry.name)")
            }
            if originals.contains(where: { entry.url.path.hasPrefix($0 + "/") }) {
                throw ExplorerError.operationFailed("Rename folders and their children in separate steps.")
            }
            let name = rule.name(for: entry, index: index).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0"), name.utf8.count <= 255 else {
                throw ExplorerError.invalidPath(name)
            }
            let target = entry.url.deletingLastPathComponent().appendingPathComponent(name)
            // Conservative on case-sensitive volumes too, so a plan is portable to common macOS volumes.
            let key = target.path.precomposedStringWithCanonicalMapping.lowercased()
            guard destinations.insert(key).inserted else { throw ExplorerError.operationFailed("Two items would have the same name: \(name)") }
            if target.path == entry.url.path { continue }
            guard !FileSystemPathIdentity.entryExists(target) else {
                throw ExplorerError.operationFailed("A target already exists: \(name). Batch rename never replaces files.")
            }
            plans.append(BatchRenamePlan(source: entry.url, destination: target, identity: identity))
        }
        return plans
    }
    public func apply(_ plans: [BatchRenamePlan]) async -> BatchRenameOutcome {
        var completed: [BatchRenamePlan] = []
        do {
            for plan in plans {
                try Task.checkCancellation()
                try FileSystemPathIdentity.requireUnchangedEntry(at: plan.source, expectedIdentity: plan.identity,
                    operation: "An item changed after the preview: \(plan.source.path)")
                try move(plan.source, plan.destination)
                completed.append(plan)
                try FileSystemPathIdentity.requireUnchangedEntry(at: plan.destination, expectedIdentity: plan.identity,
                    operation: "A renamed item changed during the operation: \(plan.destination.path)")
            }
            return outcome(completed, error: nil)
        } catch {
            var retained: [BatchRenamePlan] = []
            for plan in completed.reversed() {
                do {
                    try FileSystemPathIdentity.requireUnchangedEntry(at: plan.destination, expectedIdentity: plan.identity,
                        operation: "Rollback skipped an item changed by another process.")
                    try move(plan.destination, plan.source)
                } catch { retained.insert(plan, at: 0) }
            }
            let message = error.localizedDescription + (retained.isEmpty ? " Changes were rolled back." : " \(retained.count) renamed items remain; Undo is available. No existing target was replaced.")
            return outcome(retained, error: message)
        }
    }
    private func outcome(_ plans: [BatchRenamePlan], error: String?) -> BatchRenameOutcome {
        var result = FileOperationResult(movedItems: plans.map { FileMoveRecord(source: $0.source, destination: $0.destination) })
        for plan in plans { result.undoSourceIdentities[plan.destination.standardizedFileURL] = plan.identity }
        return BatchRenameOutcome(result: result, errorMessage: error)
    }
    public static func exclusiveMove(_ source: URL, _ destination: URL) throws {
        guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "Could not rename \(source.lastPathComponent): \(String(cString: strerror(errno)))"])
        }
    }
}
