import Darwin
import Foundation

enum FilePresence {
    case present
    case missing
    case unavailable(Int32)

    static func inspect(_ url: URL) -> FilePresence {
        var information = stat()
        return url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return .unavailable(EINVAL) }
            if lstat(path, &information) == 0 { return .present }
            let code = errno
            if code == ENOENT || code == ENOTDIR { return .missing }
            return .unavailable(code)
        }
    }
}

public enum FilePermissionFailure {
    public static func matches(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(nsError.code) { return true }
        if nsError.domain == NSCocoaErrorDomain && [CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue].contains(nsError.code) { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error { return matches(underlying) }
        return false
    }
}
