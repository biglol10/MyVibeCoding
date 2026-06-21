import AppKit
import SwiftUI

struct MainWindowView: View {
    @ObservedObject private var appState: AppState
    @ObservedObject var captureCoordinator: CaptureCoordinator
    @StateObject private var editorViewModel: EditorViewModel

    init(captureCoordinator: CaptureCoordinator, appState: AppState) {
        self.captureCoordinator = captureCoordinator
        self.appState = appState
        _editorViewModel = StateObject(wrappedValue: EditorViewModel(appState: appState))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            previewArea
            if appState.currentDocument?.kind == .screenshot {
                Divider()
                ToolInspectorView(editorViewModel: editorViewModel)
            }
            Divider()
            EditorToolbarView(
                documentKind: appState.currentDocument?.kind,
                activeTool: editorViewModel.activeTool,
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

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    await captureCoordinator.startNewCapture()
                }
            } label: {
                Label("New", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            Picker("Mode", selection: $appState.captureMode) {
                ForEach(CaptureMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)

            Spacer()

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
        .padding(12)
    }

    private var previewArea: some View {
        HStack(spacing: 0) {
            if let document = appState.currentDocument, document.kind == .screenshot {
                EditorCanvasView(document: document, editorViewModel: editorViewModel)
            } else {
                emptyOrRecordingPreview
            }

            if let result = appState.currentDocument?.ocrResult {
                Divider()
                OCRResultPanelView(result: result, onCopyText: captureCoordinator.copyOCRText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyOrRecordingPreview: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary.opacity(0.28))

            VStack(spacing: 14) {
                Image(systemName: appState.currentDocument == nil ? "viewfinder" : "record.circle")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(appState.currentDocument == nil ? "Ready to capture" : "Recording captured")
                    .font(.title3.weight(.semibold))

                Text(statusText)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusText: String {
        if let statusMessage = appState.statusMessage {
            return statusMessage
        }

        return "Choose a mode and press New."
    }
}
