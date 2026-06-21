import Foundation

public enum PermissionStatus: Equatable, Sendable {
    case available
    case fullDiskAccessRecommended
    case administratorPrivilegesRequired
    case unknownFailure(String)
}

public struct PermissionCoordinator: Sendable {
    public init() {}

    public func status(for error: Error) -> PermissionStatus {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           [CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue].contains(nsError.code) {
            return .fullDiskAccessRecommended
        }
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EACCES) {
            return .administratorPrivilegesRequired
        }
        return .unknownFailure(nsError.localizedDescription)
    }

    public func fullDiskAccessGuidance(appName: String) -> String {
        "Open System Settings, go to Privacy & Security, choose Full Disk Access, then enable \(appName). Restart the app after changing this permission."
    }
}
