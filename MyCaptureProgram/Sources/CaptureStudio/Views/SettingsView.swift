import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var shortcutManager: ShortcutManager
    @AppStorage(SettingsTab.storageKey) private var selectedTab = SettingsTab.defaultOpen.rawValue
    @State private var shortcutDraftKeys: [ShortcutAction: String] = [:]
    @State private var shortcutErrorMessage: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            outputSettings
                .tabItem { Label(SettingsTab.output.title, systemImage: SettingsTab.output.systemImage) }
                .tag(SettingsTab.output.rawValue)

            captureSettings
                .tabItem { Label(SettingsTab.capture.title, systemImage: SettingsTab.capture.systemImage) }
                .tag(SettingsTab.capture.rawValue)

            recordSettings
                .tabItem { Label(SettingsTab.record.title, systemImage: SettingsTab.record.systemImage) }
                .tag(SettingsTab.record.rawValue)

            shortcutSettings
                .tabItem { Label(SettingsTab.shortcuts.title, systemImage: SettingsTab.shortcuts.systemImage) }
                .tag(SettingsTab.shortcuts.rawValue)

            advancedSettings
                .tabItem { Label(SettingsTab.advanced.title, systemImage: SettingsTab.advanced.systemImage) }
                .tag(SettingsTab.advanced.rawValue)
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
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Copy captured image to clipboard", isOn: binding(\.copyCapturedImageToClipboard))
            timeControl(
                SettingsTimeControl.captureDelay,
                value: timeBinding(\.defaultDelaySeconds, control: .captureDelay)
            )

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 24)
    }

    private var recordSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Include system audio", isOn: binding(\.includeSystemAudio))
            Toggle("Include microphone", isOn: binding(\.includeMicrophone))
            Toggle("Show cursor in recordings", isOn: binding(\.showCursorInRecordings))
            timeControl(
                SettingsTimeControl.recordingCountdown,
                value: timeBinding(\.countdownSeconds, control: .recordingCountdown)
            )
            timeControl(
                SettingsTimeControl.recordingDuration,
                value: timeBinding(\.recordingDurationSeconds, control: .recordingDuration)
            )
            Picker("Quality", selection: recordingQualityBinding) {
                ForEach(AppSettings.RecordingQuality.allCases) { quality in
                    Text(quality.rawValue.capitalized).tag(quality)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 24)
    }

    private var shortcutSettings: some View {
        Form {
            Text(ShortcutErrorPresentation.displayMessage(for: shortcutErrorMessage))
                .font(.caption)
                .foregroundStyle(.red)
                .opacity(ShortcutErrorPresentation.opacity(for: shortcutErrorMessage))
                .frame(height: ShortcutErrorPresentation.reservedMessageHeight, alignment: .center)

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
            LabeledContent("Screen Recording", value: AdvancedPermissionStatusPresentation.screenRecording)
            LabeledContent("Microphone", value: AdvancedPermissionStatusPresentation.microphone)

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

    private func timeBinding(
        _ keyPath: WritableKeyPath<AppSettings, Int>,
        control: SettingsTimeControl
    ) -> Binding<Int> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                settingsStore.update { settings in
                    settings[keyPath: keyPath] = control.clampedValue(for: newValue)
                }
            }
        )
    }

    private func timeControl(_ control: SettingsTimeControl, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(control.title)
                Spacer()
                Text(control.formattedValue(value.wrappedValue))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(control.presets, id: \.self) { preset in
                    Button {
                        value.wrappedValue = preset
                    } label: {
                        Text(control.formattedValue(preset))
                            .fontWeight(value.wrappedValue == preset ? .semibold : .regular)
                            .frame(minWidth: 42)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer(minLength: 8)

                TextField("Seconds", value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .multilineTextAlignment(.trailing)

                Text("sec")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: 480, alignment: .leading)
    }

    private var implementedShortcutActions: [ShortcutAction] {
        ShortcutDefinition.customizableActions
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
