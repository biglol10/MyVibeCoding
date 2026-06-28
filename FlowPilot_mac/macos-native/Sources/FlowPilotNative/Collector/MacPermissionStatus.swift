import ApplicationServices
import CoreGraphics

enum MacPermissionStatus {
    static var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var screenRecordingLikelyAllowed: Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        return windows.contains { window in
            let owner = window[kCGWindowOwnerName as String] as? String
            let title = window[kCGWindowName as String] as? String
            return owner != nil && title?.isEmpty == false
        }
    }
}
