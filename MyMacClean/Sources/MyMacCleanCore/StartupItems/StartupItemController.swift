import Foundation

public enum StartupItemControllerError: Error, Equatable, LocalizedError, Sendable {
    case readOnlyItem
    case alreadyDisabled
    case alreadyEnabled
    case notDisabledByMyMacClean
    case destinationAlreadyExists

    public var errorDescription: String? {
        switch self {
        case .readOnlyItem:
            "System-wide startup items are read-only in MyMacClean."
        case .alreadyDisabled:
            "This startup item is already disabled."
        case .alreadyEnabled:
            "This startup item is already enabled."
        case .notDisabledByMyMacClean:
            "Only startup items disabled by MyMacClean can be re-enabled here."
        case .destinationAlreadyExists:
            "The target startup item file already exists."
        }
    }
}

public struct StartupItemController {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    public func disable(_ item: StartupItem) throws -> URL {
        guard item.isEditable else {
            throw StartupItemControllerError.readOnlyItem
        }
        guard item.state == .enabled else {
            throw StartupItemControllerError.alreadyDisabled
        }

        let destination = URL(fileURLWithPath: item.plistURL.path + ".mymacclean-disabled")
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw StartupItemControllerError.destinationAlreadyExists
        }

        try fileManager.moveItem(at: item.plistURL, to: destination)
        return destination
    }

    @discardableResult
    public func enable(_ item: StartupItem) throws -> URL {
        guard item.isEditable else {
            throw StartupItemControllerError.readOnlyItem
        }
        guard item.state == .disabled else {
            throw StartupItemControllerError.alreadyEnabled
        }
        guard item.disabledByRename, item.plistURL.path.hasSuffix(".mymacclean-disabled") else {
            throw StartupItemControllerError.notDisabledByMyMacClean
        }

        let destinationPath = String(item.plistURL.path.dropLast(".mymacclean-disabled".count))
        let destination = URL(fileURLWithPath: destinationPath)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw StartupItemControllerError.destinationAlreadyExists
        }

        try fileManager.moveItem(at: item.plistURL, to: destination)
        return destination
    }
}
