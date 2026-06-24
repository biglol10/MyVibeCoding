import SwiftUI

struct EditorToolbarView: View {
    let documentKind: EditorDocument.Kind?
    let activeTool: EditorTool
    let canCopy: Bool
    let canSave: Bool
    let onToolSelected: (EditorTool) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onOCR: () -> Void
    let onQuickRedact: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if documentKind == .screenshot {
                ForEach(EditorTool.allCases.filter { $0 != .ocr }) { tool in
                    toolbarButton(tool.systemImage, tool.title) {
                        onToolSelected(tool)
                    }
                    .background(activeTool == tool ? Color.accentColor.opacity(0.16) : Color.clear)
                }

                Divider().frame(height: 22)
                toolbarButton("arrow.uturn.backward", "Undo", action: onUndo)
                toolbarButton("arrow.uturn.forward", "Redo", action: onRedo)
                toolbarButton("text.viewfinder", "OCR", action: onOCR)
                toolbarButton("eye.slash", "Quick Redact", action: onQuickRedact)
            }

            if canCopy || canSave {
                if documentKind == .screenshot {
                    Divider().frame(height: 22)
                }

                if canCopy {
                    toolbarButton("doc.on.doc", "Copy", action: onCopy)
                }

                if canSave {
                    toolbarButton("square.and.arrow.down", "Save", action: onSave)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toolbarButton(_ systemName: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemName)
                .frame(width: 24, height: 24)
        }
        .disabled(documentKind == nil)
        .help(help)
    }
}
