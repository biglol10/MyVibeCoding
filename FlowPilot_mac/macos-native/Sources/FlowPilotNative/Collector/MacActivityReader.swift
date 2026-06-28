import AppKit
import CoreGraphics
import FlowPilotNativeCore

protocol ActivitySampleReader {
    func readSnapshot() -> ActivitySnapshot?
}

struct MacActivityReader: ActivitySampleReader {
    func readSnapshot() -> ActivitySnapshot? {
        let observedAt = Date()
        let frontmost = NSWorkspace.shared.frontmostApplication
        let observations = visibleWindowObservations(observedAt: observedAt, frontmost: frontmost)

        if let primary = choosePrimaryObservation(from: observations) {
            let browserTab = safariTabInfoIfAvailable(for: primary)
            return ActivitySnapshot(
                primarySample: ActivitySample(
                    observedAt: observedAt,
                    appName: browserTab?.domain ?? primary.appName,
                    processName: primary.processName,
                    windowTitle: browserTab?.title ?? primary.windowTitle ?? primary.appName,
                    domain: browserTab?.domain,
                    isIdle: false
                ),
                visibleWindows: observations.map { observation in
                    WindowObservationRecord(
                        observedAt: observation.observedAt,
                        appName: observation.appName,
                        processName: observation.processName,
                        pid: observation.pid,
                        bundleIdentifier: observation.bundleIdentifier,
                        windowTitle: observation.windowTitle,
                        isVisible: observation.isVisible,
                        isFrontmost: observation.isFrontmost,
                        isPrimary: observation == primary
                    )
                }
            )
        }

        guard let app = frontmost, !isFlowPilot(bundleIdentifier: app.bundleIdentifier, appName: app.localizedName) else {
            return nil
        }
        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let processName = app.localizedName ?? app.bundleIdentifier ?? appName
        return ActivitySnapshot(
            primarySample: ActivitySample(
                observedAt: observedAt,
                appName: appName,
                processName: processName,
                windowTitle: appName,
                domain: nil,
                isIdle: false
            ),
            visibleWindows: []
        )
    }

    private func visibleWindowObservations(
        observedAt: Date,
        frontmost: NSRunningApplication?
    ) -> [MacWindowObservation] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let runningApps = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }
        )

        return windows
            .filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
            .compactMap { window in
                guard let pidNumber = window[kCGWindowOwnerPID as String] as? NSNumber else {
                    return nil
                }
                let pid = pid_t(pidNumber.int32Value)
                let app = runningApps[pid]
                let ownerName = (window[kCGWindowOwnerName as String] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let appName = app?.localizedName ?? ownerName ?? app?.bundleIdentifier ?? "Unknown"
                if isFlowPilot(bundleIdentifier: app?.bundleIdentifier, appName: appName) {
                    return nil
                }

                let title = (window[kCGWindowName as String] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty

                return MacWindowObservation(
                    observedAt: observedAt,
                    appName: appName,
                    processName: app?.localizedName ?? ownerName ?? appName,
                    pid: pid,
                    bundleIdentifier: app?.bundleIdentifier,
                    windowTitle: title,
                    isVisible: true,
                    isFrontmost: frontmost?.processIdentifier == pid
                )
            }
    }

    private func choosePrimaryObservation(from observations: [MacWindowObservation]) -> MacWindowObservation? {
        observations.first { $0.isFrontmost } ?? observations.first
    }

    private func safariTabInfoIfAvailable(for observation: MacWindowObservation) -> BrowserTabInfo? {
        guard observation.bundleIdentifier == "com.apple.Safari" else {
            return nil
        }
        return SafariActiveTabReader().read()
    }

    private func isFlowPilot(bundleIdentifier: String?, appName: String?) -> Bool {
        if ["app.flowpilot.native", "app.flowpilot.desktop"].contains(bundleIdentifier ?? "") {
            return true
        }
        return (appName ?? "").caseInsensitiveCompare("FlowPilot") == .orderedSame
    }
}

private struct BrowserTabInfo {
    let domain: String
    let url: String
    let title: String?
}

private struct SafariActiveTabReader {
    func read() -> BrowserTabInfo? {
        let script = """
        tell application id "com.apple.Safari"
            if not (exists front window) then return ""
            set tabUrl to URL of current tab of front window
            set tabName to name of current tab of front window
            return tabUrl & linefeed & tabName
        end tell
        """

        var error: NSDictionary?
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue,
              !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let lines = result.components(separatedBy: .newlines)
        guard let url = lines.first,
              let domain = BrowserURLDomain.extract(from: url)
        else {
            return nil
        }

        return BrowserTabInfo(
            domain: domain,
            url: url,
            title: lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }
}

private struct MacWindowObservation: Equatable {
    let observedAt: Date
    let appName: String
    let processName: String
    let pid: pid_t
    let bundleIdentifier: String?
    let windowTitle: String?
    let isVisible: Bool
    let isFrontmost: Bool
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
