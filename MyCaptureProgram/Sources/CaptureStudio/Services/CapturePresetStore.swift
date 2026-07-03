import Foundation

@MainActor
public final class CapturePresetStore: ObservableObject {
    @Published public private(set) var userPresets: [CapturePreset]

    private let defaults: UserDefaults
    private let storageKey = "CaptureStudio.CapturePresets.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([CapturePreset].self, from: data) {
            userPresets = decoded
        } else {
            userPresets = []
        }
    }

    public var allPresets: [CapturePreset] {
        CapturePreset.defaultPresets + userPresets
    }

    public func save(_ preset: CapturePreset) {
        if let index = userPresets.firstIndex(where: { $0.id == preset.id || $0.name == preset.name }) {
            userPresets[index] = preset
        } else {
            userPresets.append(preset)
        }
        persist()
    }

    public func remove(id: UUID) {
        userPresets.removeAll { $0.id == id }
        persist()
    }

    public func apply(_ preset: CapturePreset, to appState: AppState, settingsStore: SettingsStore) {
        appState.captureMode = preset.captureMode
        appState.areaType = preset.areaType
        settingsStore.update { settings in
            settings.automaticallySaveScreenshots = preset.settings.automaticallySaveScreenshots
            settings.automaticallySaveRecordings = preset.settings.automaticallySaveRecordings
            settings.showInFinderAfterSave = preset.settings.showInFinderAfterSave
            settings.copyCapturedImageToClipboard = preset.settings.copyCapturedImageToClipboard
            settings.defaultDelaySeconds = preset.settings.defaultDelaySeconds
            settings.includeSystemAudio = preset.settings.includeSystemAudio
            settings.includeMicrophone = preset.settings.includeMicrophone
            settings.showCursorInRecordings = preset.settings.showCursorInRecordings
            settings.countdownSeconds = preset.settings.countdownSeconds
            settings.recordingDurationSeconds = preset.settings.recordingDurationSeconds
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(userPresets) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
