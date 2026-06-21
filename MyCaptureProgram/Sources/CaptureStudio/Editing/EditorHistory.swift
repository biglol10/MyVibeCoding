import Foundation

public struct EditorSnapshot: Codable, Equatable, Sendable {
    public var layers: [EditorLayer]
    public var selectedLayerID: UUID?

    public init(layers: [EditorLayer], selectedLayerID: UUID?) {
        self.layers = layers
        self.selectedLayerID = selectedLayerID
    }
}

public struct EditorHistory: Equatable, Sendable {
    public var current: EditorSnapshot
    public var undoStack: [EditorSnapshot]
    public var redoStack: [EditorSnapshot]

    public init(current: EditorSnapshot, undoStack: [EditorSnapshot] = [], redoStack: [EditorSnapshot] = []) {
        self.current = current
        self.undoStack = undoStack
        self.redoStack = redoStack
    }

    public mutating func apply(_ next: EditorSnapshot) {
        undoStack.append(current)
        current = next
        redoStack.removeAll()
    }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else {
            return
        }

        redoStack.append(current)
        current = previous
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else {
            return
        }

        undoStack.append(current)
        current = next
    }
}
