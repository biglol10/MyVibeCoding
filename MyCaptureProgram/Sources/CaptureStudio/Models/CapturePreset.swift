import Foundation

public struct CapturePreset: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var captureMode: CaptureMode
    public var areaType: CaptureAreaType
    public var settings: AppSettings

    public init(
        id: UUID = UUID(),
        name: String,
        captureMode: CaptureMode,
        areaType: CaptureAreaType,
        settings: AppSettings
    ) {
        self.id = id
        self.name = name
        self.captureMode = captureMode
        self.areaType = areaType
        self.settings = settings
    }

    public static var defaultPresets: [CapturePreset] {
        [
            CapturePreset(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                name: "Quick Clipboard",
                captureMode: .screenshot,
                areaType: .rectangle,
                settings: {
                    var settings = AppSettings.defaults
                    settings.automaticallySaveScreenshots = false
                    settings.copyCapturedImageToClipboard = true
                    settings.defaultDelaySeconds = 0
                    return settings
                }()
            ),
            CapturePreset(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
                name: "Bug Recording",
                captureMode: .record,
                areaType: .rectangle,
                settings: {
                    var settings = AppSettings.defaults
                    settings.recordingDurationSeconds = 12
                    settings.countdownSeconds = 3
                    settings.recordingQuality = .high
                    return settings
                }()
            ),
            CapturePreset(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
                name: "Document Save",
                captureMode: .screenshot,
                areaType: .window,
                settings: {
                    var settings = AppSettings.defaults
                    settings.automaticallySaveScreenshots = true
                    settings.copyCapturedImageToClipboard = false
                    settings.defaultDelaySeconds = 0
                    return settings
                }()
            ),
            CapturePreset(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
                name: "Share Safe",
                captureMode: .screenshot,
                areaType: .rectangle,
                settings: {
                    var settings = AppSettings.defaults
                    settings.automaticallySaveScreenshots = false
                    settings.copyCapturedImageToClipboard = false
                    settings.showInFinderAfterSave = false
                    return settings
                }()
            )
        ]
    }
}
