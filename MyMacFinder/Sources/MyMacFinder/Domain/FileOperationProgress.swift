import Foundation

public struct FileOperationID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum FileOperationKind: String, Codable, Sendable {
    case createFolder
    case rename
    case duplicate
    case copy
    case move
    case trash
    case extractZip
    case compressZip
}

public enum FileOperationPhase: String, Codable, Sendable {
    case preparing
    case resolvingConflict
    case running
    case writingArchive
    case finishing
    case completed
    case failed
    case cancelled
}

public struct FileOperationProgressSnapshot: Equatable, Sendable {
    public var id: FileOperationID
    public var kind: FileOperationKind
    public var phase: FileOperationPhase
    public var title: String
    public var currentItemName: String?
    public var completedUnitCount: Int
    public var totalUnitCount: Int?
    public var completedBytes: Int64?
    public var totalBytes: Int64?
    public var isCancellable: Bool
    public var errorMessage: String?
    public var startedAt: Date
    public var finishedAt: Date?

    public init(
        id: FileOperationID = FileOperationID(),
        kind: FileOperationKind,
        phase: FileOperationPhase = .preparing,
        title: String,
        currentItemName: String? = nil,
        completedUnitCount: Int = 0,
        totalUnitCount: Int? = nil,
        completedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        isCancellable: Bool = true,
        errorMessage: String? = nil,
        startedAt: Date = Date(),
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.phase = phase
        self.title = title
        self.currentItemName = currentItemName
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.isCancellable = isCancellable
        self.errorMessage = errorMessage
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public var fractionCompleted: Double? {
        if let completedBytes, let totalBytes, totalBytes > 0 {
            return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
        }
        if let totalUnitCount, totalUnitCount > 0 {
            return min(max(Double(completedUnitCount) / Double(totalUnitCount), 0), 1)
        }
        return nil
    }

    public var statusText: String {
        if let completedBytes, let totalBytes {
            return "\(Self.sizeText(completedBytes)) of \(Self.sizeText(totalBytes))"
        }
        if let totalUnitCount {
            return "\(completedUnitCount) of \(totalUnitCount)"
        }
        return currentItemName ?? phase.rawValue
    }

    public var isTerminal: Bool {
        phase == .completed || phase == .failed || phase == .cancelled
    }

    public func isAutoDismissibleCompletion(for id: FileOperationID) -> Bool {
        self.id == id && phase == .completed
    }

    private static func sizeText(_ bytes: Int64) -> String {
        if bytes < 1_024 {
            return "\(bytes) bytes"
        }
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = -1
        repeat {
            value /= 1_024
            unitIndex += 1
        } while value >= 1_024 && unitIndex < units.count - 1

        let rounded = value.rounded()
        if abs(value - rounded) < 0.05 {
            return "\(Int(rounded)) \(units[unitIndex])"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}
