import AppKit

public enum DocumentReplacementDecision: Equatable, Sendable {
    case save
    case discard
    case cancel
}

@MainActor
public protocol DocumentReplacementAuthorizing {
    func replacementDecision(for document: EditorDocument) async -> DocumentReplacementDecision
}

@MainActor
public struct AppKitDocumentReplacementAuthorizer: DocumentReplacementAuthorizing {
    public init() {}

    public func replacementDecision(for document: EditorDocument) async -> DocumentReplacementDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save changes before replacing the current result?"
        alert.informativeText = document.kind == .recording
            ? "This recording has not been saved."
            : "This screenshot has unsaved changes."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Changes")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .cancel
        default:
            return .discard
        }
    }
}
