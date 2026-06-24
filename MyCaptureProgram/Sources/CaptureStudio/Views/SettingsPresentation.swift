import Foundation

public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case output
    case capture
    case record
    case shortcuts
    case advanced

    public var id: String { rawValue }

    public static let defaultOpen: SettingsTab = .output
    public static let storageKey = "CaptureStudio.Settings.SelectedTab.v1"

    public var title: String {
        switch self {
        case .output:
            return "Output"
        case .capture:
            return "Capture"
        case .record:
            return "Record"
        case .shortcuts:
            return "Shortcuts"
        case .advanced:
            return "Advanced"
        }
    }

    public var systemImage: String {
        switch self {
        case .output:
            return "folder"
        case .capture:
            return "viewfinder"
        case .record:
            return "record.circle"
        case .shortcuts:
            return "keyboard"
        case .advanced:
            return "gearshape.2"
        }
    }

    public static func selectDefaultOpenTab(defaults: UserDefaults = .standard) {
        defaults.set(defaultOpen.rawValue, forKey: storageKey)
    }
}

public enum AdvancedPermissionStatusPresentation {
    public static let screenRecording = "Checked automatically when you start capture or recording."
    public static let microphone = "Checked automatically when microphone recording is enabled."
}

public enum ShortcutErrorPresentation {
    public static let reservedMessageHeight: Double = 18

    public static func displayMessage(for message: String?) -> String {
        message ?? " "
    }

    public static func opacity(for message: String?) -> Double {
        message == nil ? 0 : 1
    }
}

public struct SettingsTimeControl: Equatable, Sendable {
    public let title: String
    public let presets: [Int]
    public let range: ClosedRange<Int>

    public func clampedValue(for value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    public func formattedValue(_ value: Int) -> String {
        "\(clampedValue(for: value))s"
    }

    public static let captureDelay = SettingsTimeControl(
        title: "Default delay",
        presets: [0, 3, 5, 10],
        range: 0...10
    )

    public static let recordingCountdown = SettingsTimeControl(
        title: "Countdown",
        presets: [0, 3, 5, 10],
        range: 0...10
    )

    public static let recordingDuration = SettingsTimeControl(
        title: "Duration",
        presets: [5, 10, 30, 60, 120],
        range: 1...120
    )
}

public enum CaptureStudioGuidePresentation {
    public struct Section: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let systemImage: String
        public let items: [String]
    }

    public static let sections: [Section] = [
        Section(
            id: "capture",
            title: "Capture",
            systemImage: "viewfinder",
            items: [
                "Capture lets you drag a rectangle and save only that selected area.",
                "The app hides itself while you select, so it does not cover the target.",
                "Screenshots can auto-save, stay unsaved until Save, and copy to clipboard."
            ]
        ),
        Section(
            id: "record",
            title: "Record",
            systemImage: "record.circle",
            items: [
                "Record lets you drag a rectangle and create an MP4 of that area.",
                "Countdown controls the wait before recording starts; duration controls how long it records.",
                "After recording, the preview area plays the saved video."
            ]
        ),
        Section(
            id: "options",
            title: "Options",
            systemImage: "slider.horizontal.3",
            items: [
                "Options is for quick timing changes without opening the full settings window.",
                "The status text shows where files will save and which timing values are active."
            ]
        ),
        Section(
            id: "editor",
            title: "Editor",
            systemImage: "pencil.and.outline",
            items: [
                "Use the toolbar to draw, add arrows, boxes, circles, text, blur, OCR, and redactions.",
                "Copy exports the edited image to clipboard; Save writes the edited result to disk.",
                "Delete removes the current result from the app and moves saved files to Trash."
            ]
        ),
        Section(
            id: "settings",
            title: "Settings",
            systemImage: "gearshape",
            items: [
                "Output controls folders, auto-save, and Finder reveal behavior.",
                "Capture controls screenshot delay and clipboard behavior.",
                "Record controls audio, cursor visibility, countdown, duration, and quality.",
                "Shortcuts lets you customize hotkeys and reset them to defaults."
            ]
        ),
        Section(
            id: "permissions",
            title: "Permissions",
            systemImage: "lock.shield",
            items: [
                "macOS requires Screen Recording permission before screenshots and recordings can work.",
                "Enable CaptureStudio in System Settings > Privacy & Security > Screen & System Audio Recording.",
                "If permission was just changed, restart CaptureStudio before testing again."
            ]
        )
    ]

    public static func shouldPresentOnLaunch(hasSeenGuide: Bool) -> Bool {
        !hasSeenGuide
    }
}
