import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var automaticallySaveScreenshots: Bool
    public var automaticallySaveRecordings: Bool
    public var screenshotFolderPath: String
    public var recordingFolderPath: String
    public var showInFinderAfterSave: Bool
    public var smartFilenamesEnabled: Bool

    public var hideAppDuringCapture: Bool
    public var copyCapturedImageToClipboard: Bool
    public var defaultDelaySeconds: Int

    public var includeSystemAudio: Bool
    public var includeMicrophone: Bool
    public var showCursorInRecordings: Bool
    public var countdownSeconds: Int
    public var recordingDurationSeconds: Int
    public var recordingQuality: RecordingQuality

    public enum RecordingQuality: String, Codable, Equatable, CaseIterable, Identifiable, Sendable {
        case standard
        case high

        public var id: String { rawValue }

        public func videoBitRate(width: Int, height: Int) -> Int {
            let pixels = max(1, width) * max(1, height)
            switch self {
            case .standard:
                return pixels * 4
            case .high:
                return pixels * 8
            }
        }
    }

    public init(
        automaticallySaveScreenshots: Bool,
        automaticallySaveRecordings: Bool,
        screenshotFolderPath: String,
        recordingFolderPath: String,
        showInFinderAfterSave: Bool,
        smartFilenamesEnabled: Bool,
        hideAppDuringCapture: Bool,
        copyCapturedImageToClipboard: Bool,
        defaultDelaySeconds: Int,
        includeSystemAudio: Bool,
        includeMicrophone: Bool,
        showCursorInRecordings: Bool,
        countdownSeconds: Int,
        recordingDurationSeconds: Int,
        recordingQuality: RecordingQuality
    ) {
        self.automaticallySaveScreenshots = automaticallySaveScreenshots
        self.automaticallySaveRecordings = automaticallySaveRecordings
        self.screenshotFolderPath = screenshotFolderPath
        self.recordingFolderPath = recordingFolderPath
        self.showInFinderAfterSave = showInFinderAfterSave
        self.smartFilenamesEnabled = smartFilenamesEnabled
        self.hideAppDuringCapture = hideAppDuringCapture
        self.copyCapturedImageToClipboard = copyCapturedImageToClipboard
        self.defaultDelaySeconds = defaultDelaySeconds
        self.includeSystemAudio = includeSystemAudio
        self.includeMicrophone = includeMicrophone
        self.showCursorInRecordings = showCursorInRecordings
        self.countdownSeconds = countdownSeconds
        self.recordingDurationSeconds = recordingDurationSeconds
        self.recordingQuality = recordingQuality
    }

    private enum CodingKeys: String, CodingKey {
        case automaticallySaveScreenshots
        case automaticallySaveRecordings
        case screenshotFolderPath
        case recordingFolderPath
        case showInFinderAfterSave
        case smartFilenamesEnabled
        case hideAppDuringCapture
        case copyCapturedImageToClipboard
        case defaultDelaySeconds
        case includeSystemAudio
        case includeMicrophone
        case showCursorInRecordings
        case countdownSeconds
        case recordingDurationSeconds
        case recordingQuality
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings.defaults
        automaticallySaveScreenshots = try container.decodeIfPresent(Bool.self, forKey: .automaticallySaveScreenshots) ?? defaults.automaticallySaveScreenshots
        automaticallySaveRecordings = try container.decodeIfPresent(Bool.self, forKey: .automaticallySaveRecordings) ?? defaults.automaticallySaveRecordings
        screenshotFolderPath = try container.decodeIfPresent(String.self, forKey: .screenshotFolderPath) ?? defaults.screenshotFolderPath
        recordingFolderPath = try container.decodeIfPresent(String.self, forKey: .recordingFolderPath) ?? defaults.recordingFolderPath
        showInFinderAfterSave = try container.decodeIfPresent(Bool.self, forKey: .showInFinderAfterSave) ?? defaults.showInFinderAfterSave
        smartFilenamesEnabled = try container.decodeIfPresent(Bool.self, forKey: .smartFilenamesEnabled) ?? defaults.smartFilenamesEnabled
        hideAppDuringCapture = try container.decodeIfPresent(Bool.self, forKey: .hideAppDuringCapture) ?? defaults.hideAppDuringCapture
        copyCapturedImageToClipboard = try container.decodeIfPresent(Bool.self, forKey: .copyCapturedImageToClipboard) ?? defaults.copyCapturedImageToClipboard
        defaultDelaySeconds = Self.clamp(
            try container.decodeIfPresent(Int.self, forKey: .defaultDelaySeconds) ?? defaults.defaultDelaySeconds,
            to: 0...10
        )
        includeSystemAudio = try container.decodeIfPresent(Bool.self, forKey: .includeSystemAudio) ?? defaults.includeSystemAudio
        includeMicrophone = try container.decodeIfPresent(Bool.self, forKey: .includeMicrophone) ?? defaults.includeMicrophone
        showCursorInRecordings = try container.decodeIfPresent(Bool.self, forKey: .showCursorInRecordings) ?? defaults.showCursorInRecordings
        countdownSeconds = Self.clamp(
            try container.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? defaults.countdownSeconds,
            to: 0...10
        )
        recordingDurationSeconds = Self.clamp(
            try container.decodeIfPresent(Int.self, forKey: .recordingDurationSeconds) ?? defaults.recordingDurationSeconds,
            to: 1...120
        )
        recordingQuality = try container.decodeIfPresent(RecordingQuality.self, forKey: .recordingQuality) ?? defaults.recordingQuality
    }

    public static var desktopPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .path
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    public static var defaults: AppSettings {
        AppSettings(
            automaticallySaveScreenshots: true,
            automaticallySaveRecordings: true,
            screenshotFolderPath: desktopPath,
            recordingFolderPath: desktopPath,
            showInFinderAfterSave: false,
            smartFilenamesEnabled: true,
            hideAppDuringCapture: true,
            copyCapturedImageToClipboard: true,
            defaultDelaySeconds: 0,
            includeSystemAudio: true,
            includeMicrophone: false,
            showCursorInRecordings: true,
            countdownSeconds: 3,
            recordingDurationSeconds: 5,
            recordingQuality: .standard
        )
    }
}
