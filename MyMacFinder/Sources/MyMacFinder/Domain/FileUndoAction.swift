import Foundation

public indirect enum FileUndoAction: Equatable, Sendable {
    case created([URL])
    case copied([URL])
    case moved([FileMoveRecord])
    case renamed(FileMoveRecord)
    case trashed([FileTrashRecord])
    case extracted([URL])
    case compressed([URL])
    case restoreReplacements([FileTrashRecord])
    case compound(title: String, actions: [FileUndoAction])

    public var title: String {
        switch self {
        case .created:
            return "Undo Create"
        case .copied:
            return "Undo Copy"
        case .moved:
            return "Undo Move"
        case .renamed:
            return "Undo Rename"
        case .trashed:
            return "Undo Move to Trash"
        case .extracted:
            return "Undo Extract"
        case .compressed:
            return "Undo Compress"
        case .restoreReplacements:
            return "Undo Replace"
        case .compound(let title, _):
            return title
        }
    }
}
