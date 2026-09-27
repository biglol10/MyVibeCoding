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
        if let index = userPresets.firstIndex(where: { $0.id == preset.id }) {
            userPresets[index] = preset
        } else {
            userPresets.append(preset)
        }
        persist()
    }

    public var nextPersonalPresetName: String {
        let names = Set(userPresets.map(\.name))
        var index = 1
        while names.contains("Personal \(index)") { index += 1 }
        return "Personal \(index)"
    }

    public func matches(_ preset: CapturePreset, appState: AppState, settings: AppSettings) -> Bool {
        appState.captureMode == preset.captureMode
            && appState.areaType == preset.areaType
            && preset.applyingOptions(to: settings) == settings
    }

    public func remove(id: UUID) {
        userPresets.removeAll { $0.id == id }
        persist()
    }

    public func apply(_ preset: CapturePreset, to appState: AppState, settingsStore: SettingsStore) {
        appState.captureMode = preset.captureMode
        appState.areaType = preset.areaType
        settingsStore.update { settings in
            settings = preset.applyingOptions(to: settings)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(userPresets) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }
}
