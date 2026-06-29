import Foundation

public enum DropOperation: String, Equatable, Sendable {
    case copy
    case move
}

public enum DropSource: String, Equatable, Sendable {
    case local
    case external
}

public enum FileDropOperationResolver {
    public static func operation(
        source: DropSource,
        optionKeyPressed: Bool,
        proposedOperation: DropOperation?
    ) -> DropOperation {
        if optionKeyPressed {
            return .copy
        }

        switch source {
        case .local:
            if let proposedOperation {
                return proposedOperation
            }
            return .move
        case .external:
            return .copy
        }
    }
}
