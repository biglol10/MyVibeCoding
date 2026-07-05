import AppKit
import AVKit
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var historyStore: CaptureHistoryStore
    @EnvironmentObject private var presetStore: CapturePresetStore
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var appState: AppState
    @ObservedObject var captureCoordinator: CaptureCoordinator
    @StateObject private var editorViewModel: EditorViewModel
    @AppStorage("CaptureStudio.HasSeenGuide.v1") private var hasSeenGuide = false
    @State private var didEvaluateGuideOnAppear = false
    @State private var guideDontShowAgain = true
    @State private var trimStartText = "0"
    @State private var trimEndText = ""

    init(captureCoordinator: CaptureCoordinator, appState: AppState) {
        self.captureCoordinator = captureCoordinator
        self.appState = appState
        _editorViewModel = StateObject(wrappedValue: EditorViewModel(appState: appState))
    }

    var body: some View {
        VStack(spacing: 0) {
            quickBar

            if appState.isHistoryPresented {
                Divider()
                historyPanel
            }

            if let document = appState.currentDocument {
                Divider()
                recentResultRow(for: document)
            }

            if appState.currentDocument != nil {
                Divider()
                previewArea
            }

            if appState.currentDocument?.kind == .recording {
                Divider()
                recordingTools
            }

            if appState.currentDocument?.kind == .screenshot,
               ToolInspectorPresentation.controls(
                for: editorViewModel.activeTool,
                selectedLayer: selectedLayer
               ).isVisible {
                Divider()
                ToolInspectorView(selectedLayer: selectedLayer, editorViewModel: editorViewModel)
            }

            if let document = appState.currentDocument {
                editorToolbar(for: document)
            }
        }
        .frame(
            minWidth: MainWindowPresentation.mainWindowMinimumWidth,
            minHeight: appState.currentDocument == nil ? 128 : 430
        )
        .sheet(isPresented: guidePresentedBinding, onDismiss: handleGuideDismissed) {
            CaptureStudioGuideView(
                dontShowAgain: $guideDontShowAgain,
                onClose: { appState.isGuidePresented = false },
                onStartCapture: startCaptureFromGuide,
                onStartRecord: startRecordFromGuide
            )
        }
        .alert(item: permissionPromptBinding) { prompt in
            Alert(
                title: Text(prompt.title),
                message: Text(prompt.message),
                primaryButton: .default(Text(prompt.actionTitle)) {
                    openSystemSettings(primaryURL: prompt.systemSettingsURLString)
                    appState.permissionPrompt = nil
                },
                secondaryButton: .cancel(Text("OK")) {
                    appState.permissionPrompt = nil
                }
            )
        }
        .onAppear(perform: presentGuideOnLaunchIfNeeded)
    }

    private var permissionPromptBinding: Binding<PermissionPrompt?> {
        Binding(
            get: { appState.permissionPrompt },
            set: { appState.permissionPrompt = $0 }
        )
    }

    private var quickBar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await captureCoordinator.startScreenshotCapture() }
            } label: {
                Label("Capture", systemImage: "viewfinder")
                    .labelStyle(.titleAndIcon)
                    .frame(minWidth: 104)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.blue)
            .disabled(appState.isRecordingInProgress)
            .help("Capture area")

            if appState.isRecordingInProgress {
                Button {
                    Task { await captureCoordinator.stopActiveRecording() }
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                        .labelStyle(.titleAndIcon)
                        .frame(minWidth: 104)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .help("Stop recording")
            } else {
                Button {
                    Task { await captureCoordinator.startScreenRecording() }
                } label: {
                    Label("Record", systemImage: "record.circle")
                        .labelStyle(.titleAndIcon)
                        .frame(minWidth: 104)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .help("Record area")
            }

            quickOptionsMenu
                .disabled(appState.isRecordingInProgress)

            Button {
                openSettingsToDefaultTab()
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Settings")

            Button {
                presentGuide()
            } label: {
                Image(systemName: "questionmark.circle")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("CaptureStudio Guide")

            Button {
                appState.isHistoryPresented.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(appState.isRecordingInProgress)
            .help("Capture history")

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(MainWindowPresentation.outputSummary(settings: settingsStore.settings))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(secondarySummaryText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 150, maxWidth: 220, alignment: .trailing)
            .layoutPriority(-1)
        }
        .padding(12)
    }

    private var secondarySummaryText: String {
        if appState.currentDocument == nil, let statusMessage = appState.statusMessage {
            return statusMessage
        }

        return MainWindowPresentation.recordingSummary(settings: settingsStore.settings)
    }

    private var selectedLayer: EditorLayer? {
        guard let document = appState.currentDocument,
              let selectedLayerID = document.selectedLayerID
        else {
            return nil
        }

        return document.layers.first(where: { $0.id == selectedLayerID })
    }

    private var quickOptionsMenu: some View {
        let control = MainWindowPresentation.quickOptionsControl

        return Menu {
            Section("Presets") {
                ForEach(CapturePreset.defaultPresets) { preset in
                    Button {
                        presetStore.apply(preset, to: appState, settingsStore: settingsStore)
                    } label: {
                        quickOptionLabel(
                            title: preset.name,
                            isSelected: appState.captureMode == preset.captureMode && appState.areaType == preset.areaType
                        )
                    }
                }

                if !presetStore.userPresets.isEmpty {
                    ForEach(presetStore.userPresets) { preset in
                        Menu {
                            Button {
                                presetStore.apply(preset, to: appState, settingsStore: settingsStore)
                            } label: {
                                Label("Apply", systemImage: "checkmark")
                            }

                            Button(role: .destructive) {
                                presetStore.remove(id: preset.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            quickOptionLabel(
                                title: preset.name,
                                isSelected: appState.captureMode == preset.captureMode && appState.areaType == preset.areaType
                            )
                        }
                    }
                }

                Button("Save Current Settings as Preset") {
                    let nextIndex = presetStore.userPresets.count + 1
                    presetStore.save(
                        CapturePreset(
                            name: "Personal \(nextIndex)",
                            captureMode: appState.captureMode,
                            areaType: appState.areaType,
                            settings: settingsStore.settings
                        )
                    )
                }
            }

            Divider()

            Section("Capture Area") {
                ForEach(CaptureAreaType.allCases) { areaType in
                    Button {
                        appState.areaType = areaType
                    } label: {
                        quickOptionLabel(
                            title: areaType.title,
                            isSelected: appState.areaType == areaType
                        )
                    }
                }
            }

            Section("Screenshot Delay") {
                ForEach([0, 3, 5, 10], id: \.self) { seconds in
                    Button {
                        settingsStore.update { settings in
                            settings.defaultDelaySeconds = seconds
                        }
                    } label: {
                        quickOptionLabel(
                            title: "\(seconds)s",
                            isSelected: settingsStore.settings.defaultDelaySeconds == seconds
                        )
                    }
                }
            }

            Section("Recording Countdown") {
                ForEach([0, 3, 5, 10], id: \.self) { seconds in
                    Button {
                        settingsStore.update { settings in
                            settings.countdownSeconds = seconds
                        }
                    } label: {
                        quickOptionLabel(
                            title: "\(seconds)s",
                            isSelected: settingsStore.settings.countdownSeconds == seconds
                        )
                    }
                }
            }

            Toggle("Copy screenshots to clipboard", isOn: Binding(
                get: { settingsStore.settings.copyCapturedImageToClipboard },
                set: { value in
                    settingsStore.update { settings in
                        settings.copyCapturedImageToClipboard = value
                    }
                }
            ))

            Divider()

            Button("Change Output Folders...") {
                openSettingsToDefaultTab()
            }
        } label: {
            Text(control.title)
                .frame(minWidth: CGFloat(control.minimumWidth), alignment: .center)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(width: CGFloat(control.minimumWidth))
        .help("Quick options")
    }

    @ViewBuilder
    private func quickOptionLabel(title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func recentResultRow(for document: EditorDocument) -> some View {
        let result = MainWindowPresentation.recentResult(for: document, statusMessage: appState.statusMessage)
        return HStack(spacing: 12) {
            Image(systemName: result.systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(document.kind == .recording ? .red : .blue)
                .frame(width: 42, height: 42)
                .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.subheadline.weight(.semibold))
                Text(result.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if document.kind == .screenshot {
                Button {
                    Task { await captureCoordinator.pinCurrentScreenshot() }
                } label: {
                    Image(systemName: "pin")
                }
                .help("Pin above other windows")
            }

            if result.canCopy {
                Button {
                    Task { await captureCoordinator.copyCurrentDocument() }
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy")
            }

            if result.canReveal {
                Button {
                    captureCoordinator.revealCurrentDocument()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .help("Reveal in Finder")
            }

            if result.canSave {
                if result.requiresSave {
                    Button {
                        Task { await captureCoordinator.saveCurrentDocument() }
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Save")
                } else {
                    Button {
                        Task { await captureCoordinator.saveCurrentDocument() }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("Save copy")
                }
            }

            if result.canDelete {
                Button {
                    captureCoordinator.deleteCurrentDocument()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("History", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                TextField(MainWindowPresentation.historySearchPlaceholder, text: $appState.historySearchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Spacer()
                Button {
                    appState.isHistoryPresented = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close history")
            }

            let filteredItems = historyStore.items(matching: appState.historySearchText)
            if filteredItems.isEmpty {
                Text("No captures yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .center)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(filteredItems) { item in
                            historyItemButton(item)
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func historyItemButton(_ item: CaptureHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let thumbnail = historyThumbnail(for: item) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: item.kind == .recording ? "record.circle" : "photo")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(item.kind == .recording ? .red : .blue)
                    .frame(height: 58, alignment: .topLeading)
            }
            Text(item.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(item.fileURL.lastPathComponent)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                Button {
                    captureCoordinator.openHistoryItem(item)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .help("Open")

                Button {
                    captureCoordinator.deleteHistoryItem(item)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete")
            }
        }
        .padding(10)
        .frame(width: 170, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func historyThumbnail(for item: CaptureHistoryItem) -> NSImage? {
        if let thumbnailData = item.thumbnailData {
            return NSImage(data: thumbnailData)
        }
        if let thumbnailURL = item.thumbnailURL {
            return NSImage(contentsOf: thumbnailURL)
        }
        return nil
    }

    @ViewBuilder
    private func editorToolbar(for document: EditorDocument) -> some View {
        let result = MainWindowPresentation.recentResult(for: document, statusMessage: appState.statusMessage)
        if document.kind == .screenshot {
            Divider()
            EditorToolbarView(
                documentKind: document.kind,
                activeTool: editorViewModel.activeTool,
                canCopy: result.canCopy,
                canSave: result.canSave,
                onToolSelected: { editorViewModel.activeTool = $0 },
                onUndo: editorViewModel.undo,
                onRedo: editorViewModel.redo,
                onCopy: { Task { await captureCoordinator.copyCurrentDocument() } },
                onSave: { Task { await captureCoordinator.saveCurrentDocument() } },
                onOCR: { Task { await captureCoordinator.runOCR() } },
                onQuickRedact: { Task { await captureCoordinator.quickRedact() } }
            )
        }
    }

    private var previewArea: some View {
        HStack(spacing: 0) {
            if let document = appState.currentDocument, document.kind == .screenshot {
                EditorCanvasView(document: document, editorViewModel: editorViewModel)
            } else {
                recordingPreview
            }

            if let result = appState.currentDocument?.ocrResult {
                Divider()
                OCRResultPanelView(
                    result: result,
                    onCopyText: captureCoordinator.copyOCRText,
                    onClose: captureCoordinator.dismissOCRResult
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordingPreview: some View {
        guard let document = appState.currentDocument else {
            return AnyView(EmptyView())
        }

        let preview = MainWindowPresentation.recordingPreview(for: document, statusMessage: appState.statusMessage)
        if let fileURL = preview.fileURL {
            return AnyView(
                RecordingPlayerView(fileURL: fileURL)
                    .id(fileURL)
                    .background(.black)
            )
        }

        return AnyView(
            recordingFallbackPreview(title: preview.title, detail: preview.detail)
        )
    }

    private var recordingTools: some View {
        HStack(spacing: 10) {
            Label("Trim", systemImage: "timeline.selection")
                .font(.subheadline.weight(.semibold))
            TextField("Start", text: $trimStartText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .multilineTextAlignment(.trailing)
            TextField("End", text: $trimEndText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .multilineTextAlignment(.trailing)
            Button {
                Task {
                    await captureCoordinator.trimCurrentRecording(
                        startSeconds: Double(trimStartText) ?? 0,
                        endSeconds: Double(trimEndText) ?? Double(settingsStore.settings.recordingDurationSeconds)
                    )
                }
            } label: {
                Label("Trim Copy", systemImage: "scissors")
            }
            .disabled(appState.isRecordingInProgress)

            Divider()

            Button {
                Task { await captureCoordinator.exportCurrentRecordingAsGIF() }
            } label: {
                Label("GIF", systemImage: "square.stack.3d.forward.dottedline")
            }
            .disabled(appState.isRecordingInProgress)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func recordingFallbackPreview(title: String, detail: String) -> some View {
        ZStack {
            Rectangle()
                .fill(.quaternary.opacity(0.24))

            VStack(spacing: 12) {
                Image(systemName: "record.circle")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.red)

                Text(title)
                    .font(.title3.weight(.semibold))

                Text(detail)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var guidePresentedBinding: Binding<Bool> {
        Binding(
            get: { appState.isGuidePresented },
            set: { appState.isGuidePresented = $0 }
        )
    }

    private func presentGuide() {
        guideDontShowAgain = true
        appState.isGuidePresented = true
    }

    private func presentGuideOnLaunchIfNeeded() {
        guard !didEvaluateGuideOnAppear else {
            return
        }
        didEvaluateGuideOnAppear = true
        guard CaptureStudioGuidePresentation.shouldPresentOnLaunch(hasSeenGuide: hasSeenGuide) else {
            return
        }
        guideDontShowAgain = true
        appState.isGuidePresented = true
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

    private func handleGuideDismissed() {
        if guideDontShowAgain {
            hasSeenGuide = true
        }
        guideDontShowAgain = true
    }

    private func startCaptureFromGuide() {
        appState.isGuidePresented = false
        Task { @MainActor in
            await captureCoordinator.startScreenshotCapture()
        }
    }

    private func startRecordFromGuide() {
        appState.isGuidePresented = false
        Task { @MainActor in
            await captureCoordinator.startScreenRecording()
        }
    }

    private func openSettingsToDefaultTab() {
        SettingsTab.selectDefaultOpenTab()
        openSettings()
    }
}

private struct RecordingPlayerView: View {
    let fileURL: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                player = AVPlayer(url: fileURL)
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
