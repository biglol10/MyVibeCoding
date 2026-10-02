import AppKit
import Foundation

struct FileConflictDialogContent: Equatable, Sendable {
    var messageText: String
    var informativeText: String
    var buttonTitles: [String]

    init(conflict: FileConflict) {
        messageText = "\(conflict.operation.title) Conflict"
        informativeText = """
        An item named "\(conflict.destinationURL.lastPathComponent)" already exists in "\(conflict.destinationURL.deletingLastPathComponent().path)".

        Item \(conflict.progressDescription): \(conflict.displayName)
        """
        buttonTitles = ["Replace", "Keep Both"]
        if conflict.operation != .rename {
            buttonTitles.append("Skip")
        }
        buttonTitles.append("Cancel")
    }

    static func decision(
        for response: NSApplication.ModalResponse,
        conflict: FileConflict
    ) throws -> FileConflictDecision {
        switch response {
        case .alertFirstButtonReturn:
            return .replace
        case .alertSecondButtonReturn:
            return .keepBoth
        case .alertThirdButtonReturn where conflict.operation != .rename:
            return .skip
        default:
            throw FileOperationCancellation(operation: conflict.operation)
        }
    }
}

public final class AppKitFileConflictResolver: FileConflictResolving, @unchecked Sendable {
    public init() {}

    public func resolve(_ conflict: FileConflict) async throws -> FileConflictDecision {
        try await MainActor.run {
            let content = FileConflictDialogContent(conflict: conflict)
            let alert = NSAlert()
            alert.messageText = content.messageText
            alert.informativeText = content.informativeText
            alert.alertStyle = .warning
            for title in content.buttonTitles {
                alert.addButton(withTitle: title)
            }

            return try FileConflictDialogContent.decision(
                for: alert.runModal(),
                conflict: conflict
            )
        }
    }
}
