import SwiftUI

struct CaptureDocumentActions {
    let canSave: Bool
    let save: () -> Void
}

private struct CaptureDocumentActionsKey: FocusedValueKey {
    typealias Value = CaptureDocumentActions
}

extension FocusedValues {
    var captureDocument: CaptureDocumentActions? {
        get { self[CaptureDocumentActionsKey.self] }
        set { self[CaptureDocumentActionsKey.self] = newValue }
    }
}

struct CaptureDocumentCommands: Commands {
    @FocusedValue(\.captureDocument) private var document
    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save") { document?.save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(document?.canSave != true)
        }
    }
}
