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
    public enum Tone: String, Equatable, Sendable {
        case neutral
        case positive
        case caution
    }

    public enum MicrophoneAuthorizationState: String, Equatable, Sendable {
        case notDetermined
        case restricted
        case denied
        case authorized
    }

    public struct Row: Equatable, Sendable {
        public let title: String
        public let status: String
        public let detail: String
        public let actionTitle: String?
        public let tone: Tone
    }

    public static func screenRecordingRow(isAuthorized: Bool) -> Row {
        if isAuthorized {
            return Row(
                title: "Screen Recording",
                status: "Allowed",
                detail: "CaptureStudio can capture screenshots and screen recordings.",
                actionTitle: nil,
                tone: .positive
            )
        }

        return Row(
            title: "Screen Recording",
            status: "Action needed",
            detail: "Turn on Screen & System Audio Recording for CaptureStudio, then reopen the app.",
            actionTitle: "Open Privacy Settings",
            tone: .caution
        )
    }

    public static func microphoneRow(
        includeMicrophone: Bool,
        authorization: MicrophoneAuthorizationState
    ) -> Row {
        guard includeMicrophone else {
            return Row(
                title: "Microphone",
                status: "Off",
                detail: "Microphone access is only needed when Include microphone is turned on in the Record tab.",
                actionTitle: nil,
                tone: .neutral
            )
        }

        switch authorization {
        case .authorized:
            return Row(
                title: "Microphone",
                status: "Allowed",
                detail: "CaptureStudio can include microphone audio in recordings.",
                actionTitle: nil,
                tone: .positive
            )
        case .notDetermined:
            return Row(
                title: "Microphone",
                status: "Needs approval",
                detail: "macOS will ask for microphone access the first time you start a microphone recording.",
                actionTitle: nil,
                tone: .caution
            )
        case .restricted, .denied:
            return Row(
                title: "Microphone",
                status: "Action needed",
                detail: "Enable microphone access for CaptureStudio in System Settings before recording with mic input.",
                actionTitle: "Open Privacy Settings",
                tone: .caution
            )
        }
    }
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
                "Screenshots can auto-save, stay unsaved until Save, and copy to clipboard.",
                "History keeps recent captures searchable, and Pin floats a screenshot above other windows."
            ]
        ),
        Section(
            id: "record",
            title: "Record",
            systemImage: "record.circle",
            items: [
                "Record lets you drag a rectangle and create an MP4 of that area.",
                "Countdown controls the wait before recording starts; duration controls how long it records.",
                "After recording, the preview area plays the saved video.",
                "Use Trim Copy or GIF export when you only need the useful part of a recording."
            ]
        ),
        Section(
            id: "options",
            title: "Options",
            systemImage: "slider.horizontal.3",
            items: [
                "Options is for quick timing changes without opening the full settings window.",
                "Presets apply saved combinations for capture mode, area, timing, output, and quality.",
                "The status text shows where files will save and which timing values are active."
            ]
        ),
        Section(
            id: "editor",
            title: "Editor",
            systemImage: "pencil.and.outline",
            items: [
                "Use the toolbar to draw, add arrows, boxes, circles, text, OCR, and redactions.",
                "Copy exports the edited image to clipboard; Save writes the edited result to disk.",
                "Quick Redact finds OCR matches and adds redactions for them automatically.",
                "Delete removes the current result from the app and moves saved files to Trash."
            ]
        ),
        Section(
            id: "settings",
            title: "Settings",
            systemImage: "gearshape",
            items: [
                "Output controls folders, auto-save, Finder reveal behavior, and smart filenames.",
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
