import AppKit
import WebKit
#if SWIFT_PACKAGE
import MyMarkdownCore
#endif

@MainActor
enum AppQA {
    static func run(model: AppModel) async {
        guard let web = model.bridge.webView else { return }
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--qa-root"), args.indices.contains(index + 1) else { return }
        let root = URL(fileURLWithPath: args[index + 1], isDirectory: true).standardizedFileURL
        let allowedRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyMarkdownViewer/QA", isDirectory: true).standardizedFileURL
        guard root.path == allowedRoot.path || root.path.hasPrefix(allowedRoot.path + "/") else { return }
        let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "MyMarkdownViewer installation verification")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        var report: [String: Any] = ["platform": "WKWebView", "realIMEVerified": false]
        let originalSettings = model.settings
        let originalURL = model.documentURL
        defer { model.settings = originalSettings }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if args.contains("--qa-recover") {
                model.showRecovery = false
                let records = try await model.store.recoveries()
                guard let record = records.first(where: { $0.path == root.appendingPathComponent("native-save-test.md").path && $0.text.contains("내 편집본") }) else { throw CocoaError(.fileReadNoSuchFile) }
                await model.restore(record)
                let snapshot = try await model.bridge.snapshot()
                report["recoveryAfterProcessDeath"] = snapshot["text"] as? String == record.text && model.hasConflict
                try await model.resetQAFixture(URL(fileURLWithPath: record.path!))
                try await model.store.removeRecovery(record.id)
                if let originalURL, originalURL.path.hasPrefix(root.path + "/") { try await model.resetQAFixture(originalURL) }
                report["completed"] = true
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("relaunch-qa.json"), options: .atomic)
                return
            }
            try await Task.sleep(for: .seconds(2))
            let inspection = try await web.callAsyncJavaScript("return {theme: document.documentElement.dataset.theme, background: getComputedStyle(document.body).backgroundColor, widgets: document.querySelectorAll('.preview-widget').length, text: window.MarkdownHost.snapshot().text, width: document.documentElement.scrollWidth, viewport: innerWidth, errors: document.querySelectorAll('.render-error').length}", arguments: [:], in: nil, contentWorld: .page)
            report["initial"] = inspection
            let image = try await web.takeSnapshot(configuration: nil)
            if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: root.appendingPathComponent("editor-dark.png")) }
            model.settings.theme = .light
            _ = try await model.bridge.snapshot()
            report["lightTheme"] = try await web.callAsyncJavaScript("return document.documentElement.dataset.theme", arguments: [:], in: nil, contentWorld: .page)
            let light = try await web.takeSnapshot(configuration: nil)
            if let tiff = light.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: root.appendingPathComponent("editor-light.png")) }
            model.settings.theme = .night
            _ = try await model.bridge.snapshot()
            report["nightTheme"] = try await web.callAsyncJavaScript("return {theme: document.documentElement.dataset.theme, background: getComputedStyle(document.body).backgroundColor, foreground: getComputedStyle(document.body).color, colorScheme: getComputedStyle(document.documentElement).colorScheme}", arguments: [:], in: nil, contentWorld: .page)
            report["nightNativeAppearance"] = model.usesDarkAppearance && web.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let night = try await web.takeSnapshot(configuration: nil)
            if let tiff = night.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: root.appendingPathComponent("editor-night.png")) }
            model.settings.theme = .dark
            model.settings.autosave = true

            let fixture = root.appendingPathComponent("native-save-test.md")
            let initialData = Data([0xEF, 0xBB, 0xBF]) + Data("# 저장 검증\r\n\r\n본문입니다.\r\n".utf8)
            try initialData.write(to: fixture, options: .atomic)
            try await model.resetQAFixture(fixture)
            _ = try await model.bridge.snapshot()
            let unchangedSaved = await model.save()
            let unchangedBytes = try Data(contentsOf: fixture)
            report["unchangedBytes"] = unchangedSaved && unchangedBytes == initialData
            model.bridge.send(["type": "insert", "sessionID": model.sessionID, "documentID": fixture.path, "text": "한글 👩🏽‍💻 "])
            _ = try await model.bridge.snapshot()
            try await Task.sleep(for: .seconds(2))
            let savedData = try Data(contentsOf: fixture)
            report["autosave"] = !model.isDirty && String(data: savedData.dropFirst(3), encoding: .utf8)?.hasPrefix("한글 👩🏽‍💻 ") == true
            report["bomAndCRLF"] = savedData.starts(with: [0xEF, 0xBB, 0xBF]) && String(data: savedData.dropFirst(3), encoding: .utf8)?.contains("\r\n") == true
            model.command("undo")
            _ = try await model.bridge.snapshot()
            _ = await model.save()
            report["undoAcrossSave"] = (try Data(contentsOf: fixture)) == initialData

            model.receive(["type": "changed", "sessionID": "stale-session", "documentID": fixture.path, "baseRevision": 0, "revision": 1,
                           "changes": [["from": 0, "to": 0, "insert": "잘못된 문서"]]])
            report["staleSessionIgnored"] = !(try await model.bridge.snapshot()["text"] as? String ?? "").contains("잘못된 문서")

            try Data("# 외부 변경\n\n새 버전\n".utf8).write(to: fixture, options: .atomic)
            await model.checkExternalChange()
            report["cleanExternalReload"] = (try await model.bridge.snapshot()["text"] as? String) == "# 외부 변경\n\n새 버전\n"
            model.settings.autosave = false
            model.bridge.send(["type": "insert", "sessionID": model.sessionID, "documentID": fixture.path, "text": "내 편집본 "])
            _ = try await model.bridge.snapshot()
            try await Task.sleep(for: .milliseconds(400))
            let externalData = Data("다른 앱의 최신 문서\n".utf8)
            try externalData.write(to: fixture, options: .atomic)
            await model.checkExternalChange()
            let prevented = !(await model.save())
            let afterConflict = try Data(contentsOf: fixture)
            report["dirtyExternalConflict"] = model.hasConflict && prevented && afterConflict == externalData
            let recoveries = try await model.store.recoveries()
            let record = recoveries.first { $0.path == fixture.path && $0.text.contains("내 편집본") }
            report["recoveryPersisted"] = record != nil
            if args.contains("--qa-crash"), record != nil {
                report["crashPrepared"] = true
                model.settings = originalSettings
                UserDefaults.standard.synchronize()
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("crash-qa.json"), options: .atomic)
                kill(getpid(), SIGKILL)
                return
            }
            try await model.resetQAFixture(fixture)
            if let record {
                await model.restore(record)
                report["recoveryRestored"] = (try await model.bridge.snapshot()["text"] as? String) == record.text && model.hasConflict
                try await model.resetQAFixture(fixture)
                try await model.store.removeRecovery(record.id)
            }
            try await extendedChecks(model: model, root: root, report: &report)
            if let originalURL, originalURL.path.hasPrefix(root.path + "/") { try await model.resetQAFixture(originalURL) }
            report["completed"] = true
        } catch { report["error"] = error.localizedDescription; report["completed"] = false }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: root.appendingPathComponent("app-qa.json"), options: .atomic) }
    }

    private static func insert(_ text: String, model: AppModel) async throws {
        model.bridge.send(["type": "insert", "sessionID": model.sessionID, "documentID": model.documentID, "text": text])
        _ = try await model.bridge.snapshot()
    }

    private static func extendedChecks(model: AppModel, root: URL, report: inout [String: Any]) async throws {
        let file = root.appendingPathComponent("extended-save.md")
        let original = Data("# 안전한 원본\n\n본문\n".utf8)
        try original.write(to: file, options: .atomic)
        try await model.resetQAFixture(file)
        model.settings.autosave = false
        try await insert("저장할 편집 ", model: model)

        // A real NSFilePresenter holds the write coordination while WebKit
        // accepts another edit. This exercises the shipping save path.
        let hold = QAWriteHold(url: file)
        NSFileCoordinator.addFilePresenter(hold)
        defer { hold.release.signal(); NSFileCoordinator.removeFilePresenter(hold) }
        let saving = Task { await model.save() }
        var entered = false
        for _ in 0..<250 {
            if hold.hasEntered { entered = true; break }
            try await Task.sleep(for: .milliseconds(20))
        }
        if entered { try await insert("저장 중 추가 입력 👩🏽‍💻 ", model: model) }
        hold.release.signal()
        let saved = await saving.value
        NSFileCoordinator.removeFilePresenter(hold)
        let onDisk = try String(contentsOf: file, encoding: .utf8)
        report["editsDuringSaveStayDirty"] = entered && saved && model.isDirty && !onDisk.contains("저장 중 추가 입력")
        report["secondSaveIncludesNewerEdit"] = await model.save()
        let afterSecondSave = try String(contentsOf: file, encoding: .utf8)
        report["secondSaveIncludesNewerEdit"] = report["secondSaveIncludesNewerEdit"] as? Bool == true && afterSecondSave.contains("저장 중 추가 입력") && !model.isDirty

        let beforeDelete = try await model.bridge.snapshot()["text"] as? String
        try FileManager.default.removeItem(at: file)
        await model.checkExternalChange()
        let prevented = !(await model.save())
        let afterDelete = try await model.bridge.snapshot()["text"] as? String
        report["deletedFileNotRecreated"] = prevented && model.hasConflict && !FileManager.default.fileExists(atPath: file.path)
            && afterDelete == beforeDelete
        try original.write(to: file, options: .atomic)
        try await model.resetQAFixture(file)

        let invalid = root.appendingPathComponent("unsupported-encoding.md")
        try Data([0xFF, 0xFE, 0x41, 0x00]).write(to: invalid, options: .atomic)
        let beforeOpen = try await model.bridge.snapshot()
        await model.open(invalid)
        let afterOpen = try await model.bridge.snapshot()
        report["unsupportedOpenKeepsDocument"] = beforeOpen["text"] as? String == afterOpen["text"] as? String
            && model.documentURL == file && model.errorMessage != nil

        let readOnly = root.appendingPathComponent("read-only", isDirectory: true)
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        let protected = readOnly.appendingPathComponent("protected.md")
        try original.write(to: protected, options: .atomic)
        try await model.resetQAFixture(protected)
        try await insert("권한 오류에도 보관할 편집 ", model: model)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: readOnly.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: readOnly.path) }
        let refused = !(await model.save())
        let records = try await model.store.recoveries()
        let protectedData = try Data(contentsOf: protected)
        report["permissionFailureKeepsEditAndRecovery"] = refused && model.isDirty && protectedData == original
            && records.contains { $0.path == protected.path && $0.text.contains("권한 오류에도 보관할 편집") }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: readOnly.path)
        report["saveAfterPermissionRestored"] = await model.save()
        try await model.resetQAFixture(file)

        let large = root.appendingPathComponent("large-document.md")
        let paragraph = String(repeating: "한글과 English를 함께 읽는 문서입니다. 설명과 예제를 이어서 살펴봅니다. ", count: 3) + "\n\n"
        let largeText = "# 긴 문서\n\n" + String(repeating: paragraph, count: 10_000)
        try Data(largeText.utf8).write(to: large, options: .atomic)
        let start = Date.timeIntervalSinceReferenceDate
        try await model.resetQAFixture(large)
        _ = try await model.bridge.snapshot()
        if let web = model.bridge.webView {
            _ = try await web.callAsyncJavaScript("await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))); return true", arguments: [:], in: nil, contentWorld: .page)
            let openMs = (Date.timeIntervalSinceReferenceDate - start) * 1000
            let editing = try await web.callAsyncJavaScript("""
                const samples = [];
                for (let i = 0; i < 20; i++) {
                  const before = performance.now();
                  window.MarkdownHost.receive({type:'insert', sessionID:sessionID, documentID:documentID, text:'가'});
                  samples.push(performance.now() - before);
                }
                samples.sort((a,b) => a-b); return samples[18];
                """, arguments: ["sessionID": model.sessionID, "documentID": model.documentID], in: nil, contentWorld: .page) as? Double
            report["nativePerformance"] = ["fileReadThroughTwoFramesMs": openMs, "programmaticInputP95Ms": editing ?? -1,
                                           "bytes": largeText.utf8.count, "lines": 20_003]
            report["nativePerformanceBudget"] = openMs < 2000 && (editing ?? .infinity) < 100
        }
        try await model.resetQAFixture(file)
        for record in try await model.store.recoveries() where record.path == large.path { try await model.store.removeRecovery(record.id) }
    }
}

private final class QAWriteHold: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = { let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; return queue }()
    private let lock = NSLock()
    private var entered = false
    var hasEntered: Bool { lock.withLock { entered } }
    let release = DispatchSemaphore(value: 0)
    init(url: URL) { presentedItemURL = url }
    func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        lock.withLock { entered = true }
        _ = release.wait(timeout: .now() + 8)
        writer(nil)
    }
}
