import CoreGraphics
import Foundation

public protocol ScreenCapturePermissionChecking {
    func hasScreenCaptureAccess() -> Bool
}

public struct CoreGraphicsScreenCapturePermissionChecker: ScreenCapturePermissionChecking {
    public init() {}

    public func hasScreenCaptureAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }
}

public enum ScreenCapturePermissionError: LocalizedError, Equatable {
    case accessDenied

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Screen access is off. Enable CaptureStudio in System Settings > Privacy & Security."
        }
    }
}
