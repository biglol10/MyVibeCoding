import Foundation

public struct AppSettings: Codable, Equatable {
    public var automaticallySaveScreenshots: Bool
    public var automaticallySaveRecordings: Bool
    public var screenshotFolderPath: String
    public var recordingFolderPath: String
    public var askToSaveEditedScreenshots: Bool
    public var showInFinderAfterSave: Bool

    public var hideAppDuringCapture: Bool
    public var copyCapturedImageToClipboard: Bool
    public var copyEditsToClipboard: Bool
    public var multipleEditorWindows: Bool
    public var captureBorderEnabled: Bool
    public var defaultDelaySeconds: Int

    public var includeSystemAudio: Bool
    public var includeMicrophone: Bool
    public var microphoneDeviceName: String
    public var showCursorInRecordings: Bool
    public var countdownSeconds: Int
    public var recordingDurationSeconds: Int
    public var recordingQuality: RecordingQuality

    public enum RecordingQuality: String, Codable, Equatable, CaseIterable, Identifiable {
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

    public static var desktopPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .path
    }

    public static var defaults: AppSettings {
        AppSettings(
            automaticallySaveScreenshots: true,
            automaticallySaveRecordings: true,
            screenshotFolderPath: desktopPath,
            recordingFolderPath: desktopPath,
            askToSaveEditedScreenshots: false,
            showInFinderAfterSave: false,
            hideAppDuringCapture: true,
            copyCapturedImageToClipboard: true,
            copyEditsToClipboard: true,
            multipleEditorWindows: true,
            captureBorderEnabled: false,
            defaultDelaySeconds: 0,
            includeSystemAudio: true,
            includeMicrophone: false,
            microphoneDeviceName: "System Default",
            showCursorInRecordings: true,
            countdownSeconds: 3,
            recordingDurationSeconds: 5,
            recordingQuality: .standard
        )
    }
}
