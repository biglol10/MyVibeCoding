import AppKit
import Foundation
import MyMacCleanCore

public struct RunningApplicationMonitor: Sendable {
    private let isRunningHandler: @Sendable (InstalledApp) -> Bool

    public init() {
        self.init(isRunning: RunningApplicationMonitor.defaultIsRunning)
    }

    public init(isRunning: @escaping @Sendable (InstalledApp) -> Bool) {
        self.isRunningHandler = isRunning
    }

    public func isRunning(_ app: InstalledApp) -> Bool {
        isRunningHandler(app)
    }

    private static func defaultIsRunning(_ app: InstalledApp) -> Bool {
        NSWorkspace.shared.runningApplications.contains { runningApplication in
            if let bundleIdentifier = app.bundleIdentifier,
               runningApplication.bundleIdentifier == bundleIdentifier {
                return true
            }
            guard let runningBundleURL = runningApplication.bundleURL else { return false }
            return normalizedURL(runningBundleURL) == normalizedURL(app.bundleURL)
        }
    }

    private static func normalizedURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }
}
