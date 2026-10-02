import Foundation

public enum FileConflictOperation: String, Equatable, Sendable {
    case copy
    case move
    case rename
    case duplicate
    case extract
    case compress

    public var title: String {
        switch self {
        case .copy:
            return "Copy"
        case .move:
            return "Move"
        case .rename:
            return "Rename"
        case .duplicate:
            return "Duplicate"
        case .extract:
            return "Extract"
        case .compress:
            return "Compress"
        }
    }
}

public enum FileConflictDecision: Equatable, Sendable {
    case replace
    case keepBoth
    case skip
    case cancel
}

public struct FileConflict: Equatable, Sendable {
    public var operation: FileConflictOperation
    public var sourceURL: URL
    public var destinationURL: URL
    public var itemIndex: Int
    public var itemCount: Int

    public init(
        operation: FileConflictOperation,
        sourceURL: URL,
        destinationURL: URL,
        itemIndex: Int,
        itemCount: Int
    ) {
        self.operation = operation
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.itemIndex = itemIndex
        self.itemCount = itemCount
    }

    public var displayName: String {
        sourceURL.lastPathComponent
    }

    public var progressDescription: String {
        "\(itemIndex + 1) of \(itemCount)"
    }
}

public struct FileOperationCancellation: LocalizedError, Equatable, Sendable {
    public var operation: FileConflictOperation

    public init(operation: FileConflictOperation) {
        self.operation = operation
    }

    public var errorDescription: String? {
        "\(operation.title) cancelled."
    }
}

public protocol FileConflictResolving: Sendable {
    func resolve(_ conflict: FileConflict) async throws -> FileConflictDecision
}
