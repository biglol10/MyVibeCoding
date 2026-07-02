import Foundation

public struct EditorDocument: Equatable, Identifiable {
    public enum Kind: Equatable {
        case screenshot
        case recording
    }

    public let id: UUID
    public var kind: Kind
    public var createdAt: Date
    public var fileURL: URL?
    public var data: Data?
    public var baseImageData: Data?
    public var renderedImageData: Data?
    public var layers: [EditorLayer]
    public var selectedLayerID: UUID?
    public var ocrResult: OCRResult?
    public var undoStack: [EditorSnapshot]
    public var redoStack: [EditorSnapshot]
    public var savedSnapshot: EditorSnapshot?
    public var isDirty: Bool

    public init(
        id: UUID = UUID(),
        kind: Kind,
        createdAt: Date = Date(),
        fileURL: URL? = nil,
        data: Data? = nil,
        baseImageData: Data? = nil,
        renderedImageData: Data? = nil,
        layers: [EditorLayer] = [],
        selectedLayerID: UUID? = nil,
        ocrResult: OCRResult? = nil,
        undoStack: [EditorSnapshot] = [],
        redoStack: [EditorSnapshot] = [],
        savedSnapshot: EditorSnapshot? = nil,
        isDirty: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.fileURL = fileURL
        self.data = data
        self.baseImageData = baseImageData ?? data
        self.renderedImageData = renderedImageData
        self.layers = layers
        self.selectedLayerID = selectedLayerID
        self.ocrResult = ocrResult
        self.undoStack = undoStack
        self.redoStack = redoStack
        self.savedSnapshot = savedSnapshot ?? Self.defaultSavedSnapshot(
            fileURL: fileURL,
            layers: layers,
            selectedLayerID: selectedLayerID,
            isDirty: isDirty
        )
        self.isDirty = isDirty
    }

    public var hasEdits: Bool {
        !layers.isEmpty
    }

    public var currentImageData: Data? {
        renderedImageData ?? data ?? baseImageData
    }

    public var currentSnapshot: EditorSnapshot {
        EditorSnapshot(layers: layers, selectedLayerID: selectedLayerID)
    }

    public mutating func refreshDirtyState() {
        guard let savedSnapshot else {
            isDirty = true
            return
        }

        isDirty = layers != savedSnapshot.layers
    }

    private static func defaultSavedSnapshot(
        fileURL: URL?,
        layers: [EditorLayer],
        selectedLayerID: UUID?,
        isDirty: Bool
    ) -> EditorSnapshot? {
        guard fileURL != nil, !isDirty else {
            return nil
        }

        return EditorSnapshot(layers: layers, selectedLayerID: selectedLayerID)
    }
}
