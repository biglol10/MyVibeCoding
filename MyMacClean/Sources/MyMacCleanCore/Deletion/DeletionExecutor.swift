import Foundation

public struct DeletionExecutor: Sendable {
    public init() {}

    public func requiredConfirmationPhrase(for app: InstalledApp) -> String {
        "DELETE"
    }

    public func execute(plan: DeletionPlan, confirmation: String, force: Bool = false) async -> [DeletionItemResult] {
        guard confirmation == requiredConfirmationPhrase(for: plan.app) else {
            return plan.candidates.map {
                DeletionItemResult(path: $0.url.path, success: false, errorMessage: "confirmation phrase mismatch")
            }
        }

        return plan.candidates.map { candidate in
            do {
                if FileManager.default.fileExists(atPath: candidate.url.path) {
                    if force {
                        try prepareForForcedRemoval(at: candidate.url)
                    }
                    try FileManager.default.removeItem(at: candidate.url)
                }
                return DeletionItemResult(path: candidate.url.path, success: true, errorMessage: nil)
            } catch {
                return DeletionItemResult(path: candidate.url.path, success: false, errorMessage: error.localizedDescription)
            }
        }
    }

    private func prepareForForcedRemoval(at url: URL) throws {
        try makeWritableAndMutable(url)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return
        }

        let contents = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )?.allObjects as? [URL] ?? []

        for child in contents.reversed() {
            try? makeWritableAndMutable(child)
        }
    }

    private func makeWritableAndMutable(_ url: URL) throws {
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
