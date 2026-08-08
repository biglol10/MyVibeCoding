import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var shortcutManager: ShortcutManager
    @AppStorage(SettingsTab.storageKey) private var selectedTab = SettingsTab.defaultOpen.rawValue
    @State private var shortcutDraftKeys: [ShortcutAction: String] = [:]
    @State private var shortcutErrorMessage: String?
    @State private var permissionSnapshot = PermissionSnapshot.current(includeMicrophone: false)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: refreshPermissionSnapshot)
        .onChange(of: selectedTab) { _, newValue in
            if newValue == SettingsTab.advanced.rawValue {
                refreshPermissionSnapshot()
            }
        }
        .onChange(of: settingsStore.settings.includeMicrophone) { _, _ in
            refreshPermissionSnapshot()
        }
    }

    private var outputSettings: some View {
        settingsPage(
            title: "Output",
            subtitle: "Choose where captures are written and whether files save immediately."
        ) {
            settingsSection("Save behavior") {
                Toggle("Automatically save screenshots", isOn: binding(\.automaticallySaveScreenshots))
                Toggle("Automatically save recordings", isOn: binding(\.automaticallySaveRecordings))
                Toggle("Show in Finder after save", isOn: binding(\.showInFinderAfterSave))
                Toggle("Use app and window names in filenames", isOn: binding(\.smartFilenamesEnabled))
            }

            settingsSection("Folders") {
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
            }

            trailingActionRow {
                Button("Reset Output Defaults") {
                    settingsStore.update { settings in
                        let defaults = AppSettings.defaults
                        settings.automaticallySaveScreenshots = defaults.automaticallySaveScreenshots
                        settings.automaticallySaveRecordings = defaults.automaticallySaveRecordings
                        settings.screenshotFolderPath = defaults.screenshotFolderPath
                        settings.recordingFolderPath = defaults.recordingFolderPath
                        settings.showInFinderAfterSave = defaults.showInFinderAfterSave
                        settings.smartFilenamesEnabled = defaults.smartFilenamesEnabled
                    }
                }
            }
        }
    }

    private var captureSettings: some View {
        settingsPage(
            title: "Capture",
            subtitle: "Tune screenshot timing and clipboard behavior."
        ) {
            settingsSection("Behavior") {
                Toggle("Copy captured image to clipboard", isOn: binding(\.copyCapturedImageToClipboard))
            }

            settingsSection("Timing") {
                timeControl(
                    SettingsTimeControl.captureDelay,
                    value: timeBinding(\.defaultDelaySeconds, control: .captureDelay)
                )
            }
        }
    }

    private var recordSettings: some View {
        settingsPage(
            title: "Record",
            subtitle: "Control audio sources, capture timing, and recording quality."
        ) {
            settingsSection("Audio & cursor") {
                Toggle("Include system audio", isOn: binding(\.includeSystemAudio))
                Toggle("Include microphone", isOn: binding(\.includeMicrophone))
                Toggle("Show cursor in recordings", isOn: binding(\.showCursorInRecordings))
            }

            settingsSection("Timing") {
                timeControl(
                    SettingsTimeControl.recordingCountdown,
                    value: timeBinding(\.countdownSeconds, control: .recordingCountdown)
                )
                Divider()
                timeControl(
                    SettingsTimeControl.recordingDuration,
                    value: timeBinding(\.recordingDurationSeconds, control: .recordingDuration)
                )
            }

            settingsSection("Quality") {
                Picker("Quality", selection: recordingQualityBinding) {
                    ForEach(AppSettings.RecordingQuality.allCases) { quality in
                        Text(quality.rawValue.capitalized).tag(quality)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260, alignment: .leading)
            }
        }
    }

    private var shortcutSettings: some View {
        settingsPage(
            title: "Shortcuts",
            subtitle: "Customize keyboard shortcuts without leaving this window."
        ) {
            settingsSection("Actions") {
                Text(ShortcutErrorPresentation.displayMessage(for: shortcutErrorMessage))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .opacity(ShortcutErrorPresentation.opacity(for: shortcutErrorMessage))
                    .frame(height: ShortcutErrorPresentation.reservedMessageHeight, alignment: .center)

                ForEach(Array(implementedShortcutActions.enumerated()), id: \.element.id) { index, action in
                    shortcutRow(for: action)
                    if index < implementedShortcutActions.count - 1 {
                        Divider()
                    }
                }
            }

            trailingActionRow {
                Button("Reset All Defaults") {
                    shortcutManager.resetAllToDefaults()
                    shortcutDraftKeys.removeAll()
                    shortcutErrorMessage = nil
                }
            }
        }
    }

    private var advancedSettings: some View {
        settingsPage(
            title: "Advanced",
            subtitle: "Check privacy access and reset local app state when something gets stuck."
        ) {
            settingsSection("Permissions") {
                permissionRow(
                    AdvancedPermissionStatusPresentation.screenRecordingRow(
                        isAuthorized: permissionSnapshot.screenRecordingAuthorized
                    ),
                    action: openScreenRecordingSettings
                )
                Divider()
                permissionRow(
                    AdvancedPermissionStatusPresentation.microphoneRow(
                        includeMicrophone: settingsStore.settings.includeMicrophone,
                        authorization: permissionSnapshot.microphoneAuthorization
                    ),
                    action: openMicrophoneSettings
                )
                trailingActionRow {
                    Button("Refresh Status") {
                        refreshPermissionSnapshot()
                    }
                }
            }

            settingsSection("Reset") {
                Text("Reset settings and shortcut overrides back to their defaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                trailingActionRow {
                    Button("Reset All Settings") {
                        settingsStore.reset()
                        shortcutManager.resetAllToDefaults()
                        shortcutDraftKeys.removeAll()
                        shortcutErrorMessage = nil
                        refreshPermissionSnapshot()
                    }
                }
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var implementedShortcutActions: [ShortcutAction] {
        ShortcutDefinition.customizableActions
    }

    private func folderRow(
        title: String,
        path: String,
        setting: WritableKeyPath<AppSettings, String>
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
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
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(displayValue(for: action))
                    .font(.caption.weight(.medium))
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

            if let registrationFailure = shortcutManager.registrationFailures[action] {
                Text(registrationFailure)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
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
            case .unsafeModifiers:
                shortcutErrorMessage = "Use Command, Option, or Control so normal typing is not captured."
            }
        } catch {
            shortcutErrorMessage = "Shortcut could not be saved."
        }
    }

    private func settingsPage<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func trailingActionRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Spacer()
            content()
        }
    }

    private func permissionRow(
        _ row: AdvancedPermissionStatusPresentation.Row,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(row.status)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor(for: row.tone).opacity(0.18), in: Capsule())
                    .foregroundStyle(statusColor(for: row.tone))
            }

            Text(row.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle = row.actionTitle {
                Button(actionTitle) {
                    action()
                }
            }
        }
    }

    private func statusColor(for tone: AdvancedPermissionStatusPresentation.Tone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .positive:
            return .green
        case .caution:
            return .orange
        }
    }

    private func refreshPermissionSnapshot() {
        permissionSnapshot = PermissionSnapshot.current(includeMicrophone: settingsStore.settings.includeMicrophone)
    }

    private func openScreenRecordingSettings() {
        openSystemSettings(primaryURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func openMicrophoneSettings() {
        openSystemSettings(primaryURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    private func openSystemSettings(primaryURL: String) {
        let candidates: [URL?] = [
            URL(string: primaryURL),
            URL(string: "x-apple.systempreferences:com.apple.preference.security"),
            URL(fileURLWithPath: "/System/Applications/System Settings.app")
        ]

        for candidate in candidates.compactMap({ $0 }) {
            if NSWorkspace.shared.open(candidate) {
                return
            }
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

private struct PermissionSnapshot: Equatable {
    let screenRecordingAuthorized: Bool
    let microphoneAuthorization: AdvancedPermissionStatusPresentation.MicrophoneAuthorizationState

    static func current(includeMicrophone: Bool) -> PermissionSnapshot {
        PermissionSnapshot(
            screenRecordingAuthorized: CGPreflightScreenCaptureAccess(),
            microphoneAuthorization: includeMicrophone
                ? mapMicrophoneStatus(AVCaptureDevice.authorizationStatus(for: .audio))
                : .notDetermined
        )
    }

    private static func mapMicrophoneStatus(
        _ status: AVAuthorizationStatus
    ) -> AdvancedPermissionStatusPresentation.MicrophoneAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        @unknown default:
            return .denied
        }
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
