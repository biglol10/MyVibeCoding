import Darwin
import Foundation

public struct ScanIssue: Equatable, Identifiable, Sendable {
    public var id: String { path + "\0" + message }

    public let path: String
    public let message: String
    public let permissionRelated: Bool

    public init(path: String, message: String, permissionRelated: Bool) {
        self.path = path
        self.message = message
        self.permissionRelated = permissionRelated
    }

    public static func from(path: URL, error: Error) -> ScanIssue {
        let nsError = error as NSError
        let cocoaPermissionCodes = [
            CocoaError.fileReadNoPermission.rawValue,
            CocoaError.fileWriteNoPermission.rawValue
        ]
        let posixPermissionCodes = [Int(EACCES), Int(EPERM)]
        let permissionRelated =
            (nsError.domain == NSCocoaErrorDomain && cocoaPermissionCodes.contains(nsError.code))
            || (nsError.domain == NSPOSIXErrorDomain && posixPermissionCodes.contains(nsError.code))

        return ScanIssue(
            path: path.standardizedFileURL.path,
            message: nsError.localizedDescription,
            permissionRelated: permissionRelated
        )
    }
}

public struct ScanResult<Value: Sendable>: Sendable {
    public let value: Value
    public let issues: [ScanIssue]

    public init(value: Value, issues: [ScanIssue]) {
        self.value = value
        self.issues = issues
    }
}

extension Array where Element == ScanIssue {
    func deduplicatedAndSorted() -> [ScanIssue] {
        var seen: Set<String> = []
        return sorted {
            if $0.path == $1.path { return $0.message < $1.message }
            return $0.path < $1.path
        }.filter { seen.insert($0.id).inserted }
    }
}
