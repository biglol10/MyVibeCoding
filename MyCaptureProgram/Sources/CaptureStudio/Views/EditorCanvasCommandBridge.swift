import AppKit
import SwiftUI

/// Route standard Edit menu actions through the responder chain. Text fields keep
/// their own native copy, delete and undo behavior while they are first responder.
struct EditorCanvasCommandBridge: NSViewRepresentable {
    @ObservedObject var viewModel: EditorViewModel
    var onCopy: () -> Void

    func makeNSView(context: Context) -> EditorCommandTarget {
        EditorCommandTarget()
    }

    func updateNSView(_ view: EditorCommandTarget, context: Context) {
        view.viewModel = viewModel
        view.onCopy = onCopy
        if view.focusRequest != viewModel.canvasFocusRequest {
            view.focusRequest = viewModel.canvasFocusRequest
            if !viewModel.isInteractionBlocked { view.window?.makeFirstResponder(view) }
        }
    }
}

final class EditorCommandTarget: NSView, NSUserInterfaceValidations {
    var viewModel: EditorViewModel?
    var onCopy: () -> Void = {}
    var focusRequest = 0
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if focusRequest > 0, canEdit { window?.makeFirstResponder(self) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @objc func undo(_ sender: Any?) { if canEdit { viewModel?.undo() } }
    @objc func redo(_ sender: Any?) { if canEdit { viewModel?.redo() } }
    @objc func copy(_ sender: Any?) { if canEdit { onCopy() } }
    @objc func delete(_ sender: Any?) { if canEdit { viewModel?.deleteSelectedLayer() } }

    private var canEdit: Bool { viewModel?.isInteractionBlocked == false }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        guard canEdit else { return false }
        switch item.action {
        case #selector(undo(_:)): return viewModel?.canUndo == true
        case #selector(redo(_:)): return viewModel?.canRedo == true
        case #selector(copy(_:)): return true
        case #selector(delete(_:)): return viewModel?.canDeleteSelectedLayer == true
        default: return false
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 {
            delete(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
