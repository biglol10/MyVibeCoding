import XCTest
@testable import CaptureStudio

@MainActor
final class CaptureCoordinatorEditingTests: XCTestCase {
    func testSaveCurrentScreenshotUsesRenderedDataWhenLayersExist() throws {
        let appState = AppState()
        let settingsStore = SettingsStore(defaults: isolatedDefaults("saveRendered"))
        let outputDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        settingsStore.update { settings in
            settings.screenshotFolderPath = outputDirectory.path
        }
        let original = Data([0x89, 0x50, 0x4E, 0x47, 0x00])
        let rendered = Data([0x89, 0x50, 0x4E, 0x47, 0x99])
        let layer = EditorLayer.redaction(
            RedactionLayer(
                frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
            )
        )
        appState.currentDocument = EditorDocument(kind: .screenshot, createdAt: Date(timeIntervalSince1970: 50), data: original, layers: [layer])
        let renderer = MockImageRenderService(renderedData: rendered)
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: EditingMockScreenshotService(),
            fileOutputService: FileOutputService(),
            imageRenderService: renderer
        )

        coordinator.saveCurrentDocument()

        let fileURL = try XCTUnwrap(appState.currentDocument?.fileURL)
        XCTAssertEqual(try Data(contentsOf: fileURL), rendered)
        XCTAssertEqual(renderer.renderCallCount, 1)
    }

    func testCopyCurrentScreenshotUsesRenderedDataWhenLayersExist() {
        let appState = AppState()
        let settingsStore = SettingsStore(defaults: isolatedDefaults("copyRendered"))
        let original = Data([0x89, 0x50, 0x4E, 0x47, 0x00])
        let rendered = Data([0x89, 0x50, 0x4E, 0x47, 0x88])
        let layer = EditorLayer.redaction(
            RedactionLayer(
                frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                style: LayerStyle(strokeColor: .black, fillColor: .black, lineWidth: 1)
            )
        )
        appState.currentDocument = EditorDocument(kind: .screenshot, data: original, layers: [layer])
        let renderer = MockImageRenderService(renderedData: rendered)
        let clipboard = EditingMockClipboardService()
        let coordinator = CaptureCoordinator(
            appState: appState,
            settingsStore: settingsStore,
            screenshotService: EditingMockScreenshotService(),
            imageRenderService: renderer,
            clipboardService: clipboard
        )

        coordinator.copyCurrentDocument()

        XCTAssertEqual(clipboard.copiedPNGData, rendered)
        XCTAssertEqual(renderer.renderCallCount, 1)
    }

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let suiteName = "CaptureCoordinatorEditingTests.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class MockImageRenderService: ImageRenderServicing {
    let renderedData: Data
    var renderCallCount = 0

    init(renderedData: Data) {
        self.renderedData = renderedData
    }

    func renderPNG(basePNGData: Data, layers: [EditorLayer]) throws -> Data {
        renderCallCount += 1
        return renderedData
    }
}

private final class EditingMockScreenshotService: ScreenshotServicing {
    func captureImage(selection: CaptureSelection) async throws -> ScreenshotResult {
        ScreenshotResult(pngData: Data([0x89, 0x50, 0x4E, 0x47]), createdAt: Date(timeIntervalSince1970: 20))
    }
}

private final class EditingMockClipboardService: ClipboardServicing {
    var copiedPNGData: Data?
    var copiedText: String?

    func copyPNGData(_ data: Data) {
        copiedPNGData = data
    }

    func copyText(_ text: String) {
        copiedText = text
    }
}
