import AppKit
import AVKit
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var appState: AppState
    @ObservedObject var captureCoordinator: CaptureCoordinator
    @StateObject private var editorViewModel: EditorViewModel
    @AppStorage("CaptureStudio.HasSeenGuide.v1") private var hasSeenGuide = false
    @State private var didEvaluateGuideOnAppear = false
    @State private var guideDontShowAgain = true

    init(captureCoordinator: CaptureCoordinator, appState: AppState) {
        self.captureCoordinator = captureCoordinator
        self.appState = appState
        _editorViewModel = StateObject(wrappedValue: EditorViewModel(appState: appState))
    }

    var body: some View {
        VStack(spacing: 0) {
            quickBar

            if let document = appState.currentDocument {
                Divider()
                recentResultRow(for: document)
            }

            if appState.currentDocument != nil {
                Divider()
                previewArea
            }

            if appState.currentDocument?.kind == .screenshot {
                Divider()
                ToolInspectorView(editorViewModel: editorViewModel)
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
        .onAppear(perform: presentGuideOnLaunchIfNeeded)
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
            .help("Capture area")

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

            quickOptionsMenu

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

    private var quickOptionsMenu: some View {
        let control = MainWindowPresentation.quickOptionsControl

        return Menu {
            Section("Screenshot Delay") {
                ForEach([0, 3, 5, 10], id: \.self) { seconds in
                    Button("\(seconds)s") {
                        settingsStore.update { settings in
                            settings.defaultDelaySeconds = seconds
                        }
                    }
                }
            }

            Section("Recording Countdown") {
                ForEach([0, 3, 5, 10], id: \.self) { seconds in
                    Button("\(seconds)s") {
                        settingsStore.update { settings in
                            settings.countdownSeconds = seconds
                        }
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

            if result.canCopy {
                Button {
                    captureCoordinator.copyCurrentDocument()
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
                        captureCoordinator.saveCurrentDocument()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Save")
                } else {
                    Button {
                        captureCoordinator.saveCurrentDocument()
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

    @ViewBuilder
    private func editorToolbar(for document: EditorDocument) -> some View {
        let result = MainWindowPresentation.recentResult(for: document, statusMessage: appState.statusMessage)
        if document.kind == .screenshot || result.canCopy || result.canSave {
            Divider()
            EditorToolbarView(
                documentKind: document.kind,
                activeTool: editorViewModel.activeTool,
                canCopy: result.canCopy,
                canSave: result.canSave,
                onToolSelected: { editorViewModel.activeTool = $0 },
                onUndo: editorViewModel.undo,
                onRedo: editorViewModel.redo,
                onCopy: captureCoordinator.copyCurrentDocument,
                onSave: captureCoordinator.saveCurrentDocument,
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
                OCRResultPanelView(result: result, onCopyText: captureCoordinator.copyOCRText)
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
