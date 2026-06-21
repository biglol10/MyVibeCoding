import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var shortcutManager: ShortcutManager
    @State private var shortcutDraftKeys: [ShortcutAction: String] = [:]
    @State private var shortcutErrorMessage: String?

    var body: some View {
        TabView {
            outputSettings
                .tabItem { Label("Output", systemImage: "folder") }

            captureSettings
                .tabItem { Label("Capture", systemImage: "viewfinder") }

            recordSettings
                .tabItem { Label("Record", systemImage: "record.circle") }

            shortcutSettings
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            advancedSettings
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
        }
        .padding(20)
    }

    private var outputSettings: some View {
        Form {
            Toggle("Automatically save screenshots", isOn: binding(\.automaticallySaveScreenshots))
            Toggle("Automatically save recordings", isOn: binding(\.automaticallySaveRecordings))
            Toggle("Show in Finder after save", isOn: binding(\.showInFinderAfterSave))

            folderRow(
                title: "Screenshot folder",
                path: settingsStore.settings.screenshotFolderPath,
                setting: \.screenshotFolderPath
            )
            folderRow(
                title: "Recording folder",
                path: settingsStore.settings.recordingFolderPath,
                setting: \.recordingFolderPath
            )

            Button("Reset Output Defaults") {
                settingsStore.update { settings in
                    let defaults = AppSettings.defaults
                    settings.automaticallySaveScreenshots = defaults.automaticallySaveScreenshots
                    settings.automaticallySaveRecordings = defaults.automaticallySaveRecordings
                    settings.screenshotFolderPath = defaults.screenshotFolderPath
                    settings.recordingFolderPath = defaults.recordingFolderPath
                    settings.showInFinderAfterSave = defaults.showInFinderAfterSave
                }
            }
        }
    }

    private var captureSettings: some View {
        Form {
            Toggle("Copy captured image to clipboard", isOn: binding(\.copyCapturedImageToClipboard))
            Stepper("Default delay: \(settingsStore.settings.defaultDelaySeconds)s", value: intBinding(\.defaultDelaySeconds), in: 0...10)
        }
    }

    private var recordSettings: some View {
        Form {
            Toggle("Include system audio", isOn: binding(\.includeSystemAudio))
            Toggle("Include microphone", isOn: binding(\.includeMicrophone))
            Toggle("Show cursor in recordings", isOn: binding(\.showCursorInRecordings))
            Stepper("Countdown: \(settingsStore.settings.countdownSeconds)s", value: intBinding(\.countdownSeconds), in: 0...10)
            Stepper("Duration: \(settingsStore.settings.recordingDurationSeconds)s", value: intBinding(\.recordingDurationSeconds), in: 1...120)
            Picker("Quality", selection: recordingQualityBinding) {
                ForEach(AppSettings.RecordingQuality.allCases) { quality in
                    Text(quality.rawValue.capitalized).tag(quality)
                }
            }
        }
    }

    private var shortcutSettings: some View {
        Form {
            if let shortcutErrorMessage {
                Text(shortcutErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ForEach(implementedShortcutActions) { action in
                shortcutRow(for: action)
            }

            Button("Reset All Defaults") {
                shortcutManager.resetAllToDefaults()
                shortcutDraftKeys.removeAll()
                shortcutErrorMessage = nil
            }
        }
    }

    private var advancedSettings: some View {
        Form {
            LabeledContent("Screen Recording", value: "Checked when capture starts")
            LabeledContent("Microphone", value: "Checked when recording starts")

            Button("Reset All Settings") {
                settingsStore.reset()
                shortcutManager.resetAllToDefaults()
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                settingsStore.update { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<AppSettings, Int>) -> Binding<Int> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                settingsStore.update { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private var implementedShortcutActions: [ShortcutAction] {
        [.newScreenshot, .newRecording, .openSettings]
    }

    private func folderRow(
        title: String,
        path: String,
        setting: WritableKeyPath<AppSettings, String>
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button("Choose...") {
                chooseFolder(title: title, setting: setting)
            }
        }
    }

    private func chooseFolder(title: String, setting: WritableKeyPath<AppSettings, String>) {
        let panel = NSOpenPanel()
        panel.title = "Choose \(title)"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        settingsStore.update { settings in
            settings[keyPath: setting] = url.path
        }
    }

    private func shortcutRow(for action: ShortcutAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(action.title)
                Spacer()
                Text(displayValue(for: action))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(ShortcutModifier.allCases, id: \.self) { modifier in
                    Toggle(modifier.shortTitle, isOn: modifierBinding(modifier, for: action))
                        .toggleStyle(.button)
                }

                TextField("Key", text: shortcutKeyBinding(for: action))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .onSubmit {
                        applyShortcutDraft(for: action)
                    }

                Button("Apply") {
                    applyShortcutDraft(for: action)
                }

                Button("Reset") {
                    shortcutManager.resetToDefault(action)
                    shortcutDraftKeys[action] = nil
                    shortcutErrorMessage = nil
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func shortcutKeyBinding(for action: ShortcutAction) -> Binding<String> {
        Binding(
            get: {
                shortcutDraftKeys[action] ?? shortcutManager.bindings[action]?.key ?? ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                shortcutDraftKeys[action] = String(trimmed.prefix(1)).uppercased()
            }
        )
    }

    private func modifierBinding(_ modifier: ShortcutModifier, for action: ShortcutAction) -> Binding<Bool> {
        Binding(
            get: {
                shortcutManager.bindings[action]?.modifiers.contains(modifier) ?? false
            },
            set: { isEnabled in
                guard let current = shortcutManager.bindings[action] else {
                    return
                }

                var modifiers = current.modifiers
                if isEnabled {
                    modifiers.append(modifier)
                } else {
                    modifiers.removeAll { $0 == modifier }
                }

                setShortcutBinding(
                    ShortcutBinding(key: shortcutDraftKeys[action] ?? current.key, modifiers: Array(Set(modifiers))),
                    for: action
                )
            }
        )
    }

    private func applyShortcutDraft(for action: ShortcutAction) {
        guard let current = shortcutManager.bindings[action] else {
            return
        }

        let key = shortcutDraftKeys[action] ?? current.key
        guard !key.isEmpty else {
            shortcutErrorMessage = "Shortcut key cannot be empty."
            return
        }

        setShortcutBinding(ShortcutBinding(key: key, modifiers: current.modifiers), for: action)
    }

    private func setShortcutBinding(_ binding: ShortcutBinding, for action: ShortcutAction) {
        do {
            try shortcutManager.setBinding(binding, for: action)
            shortcutDraftKeys[action] = binding.key
            shortcutErrorMessage = nil
        } catch let error as ShortcutManager.ShortcutError {
            switch error {
            case .duplicateBinding(let existingAction):
                shortcutErrorMessage = "Shortcut already used by \(existingAction.title)."
            }
        } catch {
            shortcutErrorMessage = "Shortcut could not be saved."
        }
    }

    private var recordingQualityBinding: Binding<AppSettings.RecordingQuality> {
        Binding(
            get: { settingsStore.settings.recordingQuality },
            set: { newValue in
                settingsStore.update { settings in
                    settings.recordingQuality = newValue
                }
            }
        )
    }

    private func displayValue(for action: ShortcutAction) -> String {
        if let binding = shortcutManager.bindings[action] {
            return binding.displayValue
        }

        return "Unassigned"
    }
}

private extension ShortcutModifier {
    var shortTitle: String {
        switch self {
        case .command:
            return "Cmd"
        case .shift:
            return "Shift"
        case .option:
            return "Opt"
        case .control:
            return "Ctrl"
        }
    }
}
