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

enum ScreenCaptureApplicationMatcher {
    static func matches(
        applicationProcessID: pid_t,
        applicationBundleIdentifier: String?,
        currentProcessID: pid_t,
        currentBundleIdentifier: String?
    ) -> Bool {
        if applicationProcessID == currentProcessID {
            return true
        }
        guard let currentBundleIdentifier, !currentBundleIdentifier.isEmpty else {
            return false
        }
        return applicationBundleIdentifier == currentBundleIdentifier
    }
}

enum ScreenCaptureContentFilterError: LocalizedError, Equatable {
    case currentApplicationUnavailable

    var errorDescription: String? {
        "CaptureStudio could not safely exclude its own windows. Try the capture again."
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
