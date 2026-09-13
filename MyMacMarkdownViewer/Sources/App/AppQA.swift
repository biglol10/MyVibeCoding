import AppKit
import PDFKit
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
        if args.contains("--qa-reveal-current") {
            await FileRevealQA.run(model: model, root: root)
            return
        }
        if args.contains("--qa-code-language") {
            await codeLanguageChecks(model: model, web: web, root: root)
            return
        }
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
            try await exportChecks(model: model, root: root, report: &report)
            try await extendedChecks(model: model, root: root, report: &report)
            try await workspaceChecks(model: model, root: root, report: &report)
            let longExtension = root.appendingPathComponent("확장자 검증.MARKDOWN")
            let longExtensionText = "# Markdown 확장자\n\n한글 문서 원문 보존\n"
            try Data(longExtensionText.utf8).write(to: longExtension)
            try await model.resetQAFixture(longExtension)
            let extensionSnapshot = try await model.bridge.snapshot()
            report["markdownExtensionNativeOpen"] = extensionSnapshot["text"] as? String == longExtensionText
            let extensionSaved = await model.save()
            let extensionBytes = try Data(contentsOf: longExtension)
            report["markdownExtensionNativeSave"] = extensionSaved && extensionBytes == Data(longExtensionText.utf8)
            if let originalURL, originalURL.path.hasPrefix(root.path + "/") { try await model.resetQAFixture(originalURL) }
            report["completed"] = true
        } catch {
            let native = error as NSError
            report["error"] = error.localizedDescription
            report["errorDomain"] = native.domain
            report["errorCode"] = native.code
            report["errorDetails"] = native.userInfo.reduce(into: [String: String]()) { values, entry in
                values[String(describing: entry.key)] = String(describing: entry.value)
            }
            report["completed"] = false
        }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: root.appendingPathComponent("app-qa.json"), options: .atomic) }
    }

    private static func codeLanguageChecks(model: AppModel, web: WKWebView, root: URL) async {
        var report: [String: Any] = ["platform": "native macOS WKWebView", "physicalIMEVerified": false]
        let previous = model.settings
        defer { model.settings = previous }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("code-language.md")
            let source = "# 코드 언어\n\n~~~py  title=\"Example\"\nvalue = \"한글 보존\"\nprint(value)\n~~~\n\n뒤 문단\n"
            func encoded(_ text: String) -> Data { Data([0xEF, 0xBB, 0xBF]) + Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8) }
            try encoded(source).write(to: file, options: .atomic)
            model.settings.theme = .night
            model.settings.autosave = false
            try await model.resetQAFixture(file)
            _ = try await model.bridge.snapshot()
            try await Task.sleep(for: .milliseconds(500))
            let selected = try await web.callAsyncJavaScript("""
                const select = document.querySelector('select[aria-label="코드 언어"]');
                if (!select) throw new Error('Missing language selector');
                select.value = 'javascript'; select.dispatchEvent(new Event('change', {bubbles:true}));
                // Language edits update CodeMirror synchronously. Waiting for
                // a paint can stall while this QA window is in the background.
                return window.MarkdownHost.snapshot().text;
                """, arguments: [:], in: nil, contentWorld: .page) as? String
            let changed = source.replacingOccurrences(of: "~~~py  title=", with: "~~~javascript  title=")
            report["changedOnlyLanguage"] = selected == changed
            let changedSaved = await model.save()
            let changedBytes = try Data(contentsOf: file)
            report["savedWithBOMAndCRLF"] = changedSaved && changedBytes == encoded(changed)
            model.command("undo")
            let undone = try await model.bridge.snapshot()["text"] as? String
            let undoSaved = await model.save()
            let undoneBytes = try Data(contentsOf: file)
            report["undoAndSave"] = undone == source && undoSaved && undoneBytes == encoded(source)
            model.command("redo")
            let redone = try await model.bridge.snapshot()["text"] as? String
            report["redo"] = redone == changed
            try await Task.sleep(for: .milliseconds(250))
            // Native UI capture can be performed by the external QA runner.
            // Do not make save/undo verification depend on an offscreen
            // WKWebView snapshot callback when that capture is disabled.
            if !ProcessInfo.processInfo.arguments.contains("--qa-no-snapshot") {
                let image = try await web.takeSnapshot(configuration: nil)
                if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: root.appendingPathComponent("code-language-night.png"))
                }
            }
            model.command("undo")
            _ = try await model.bridge.snapshot()
            let restored = await model.save()
            let restoredBytes = try Data(contentsOf: file)
            report["restoredOriginalBytes"] = restored && restoredBytes == encoded(source)
            report["passed"] = ["changedOnlyLanguage", "savedWithBOMAndCRLF", "undoAndSave", "redo", "restoredOriginalBytes"].allSatisfy { report[$0] as? Bool == true }
        } catch {
            report["passed"] = false
            report["error"] = error.localizedDescription
        }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: root.appendingPathComponent("code-language.json"), options: .atomic)
        }
    }

    private static func insert(_ text: String, model: AppModel) async throws {
        model.bridge.send(["type": "insert", "sessionID": model.sessionID, "documentID": model.documentID, "text": text])
        _ = try await model.bridge.snapshot()
    }

    private static func exportChecks(model: AppModel, root: URL, report: inout [String: Any]) async throws {
        let file = root.appendingPathComponent("export-test.md")
        let assets = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        try pixel.write(to: assets.appendingPathComponent("pixel.png"), options: .atomic)
        model.access.grant(root)
        let markdown = """
        # 내보내기 검증

        ![로컬 이미지](assets/pixel.png)

        인라인 수식 $x^2 + y^2$과 수식 블록입니다.

        $$
        \\int_0^1 x^2 dx
        $$

        | 이름 | 값 |
        | --- | ---: |
        | 한글 | 123 |

        ```mermaid
        graph LR
          A[시작] --> B[완료]
        ```

        """ + String(repeating: "한글 본문과 **굵은 글씨**를 여러 페이지에 출력합니다.\n\n", count: 180)
            + "\nENDQA9C3A\n"
        try Data(markdown.utf8).write(to: file, options: .atomic)
        try await model.resetQAFixture(file)
        let html = try await model.bridge.exportHTML()
        let htmlURL = root.appendingPathComponent("export-test.html")
        try Data(html.utf8).write(to: htmlURL, options: .atomic)
        report["standaloneHTMLExport"] = html.localizedCaseInsensitiveContains("<!doctype html")
            && html.localizedCaseInsensitiveContains("<style") && html.contains("내보내기 검증")
            && html.contains("data:image/png;base64,") && html.contains("class=\"katex")
            && html.localizedCaseInsensitiveContains("<table") && html.contains("<svg") && !html.contains("app://")

        let pdfURL = root.appendingPathComponent("export-test.pdf")
        try await HTMLPrintRenderer().savePDF(html: html, to: pdfURL)
        let pdfData = try Data(contentsOf: pdfURL)
        let pdfDocument = PDFDocument(url: pdfURL)
        let pageCount = pdfDocument?.pageCount ?? 0
        let pdfText = pdfDocument?.string ?? ""
        let firstInk = try pdfDocument?.page(at: 0).map { try renderedInk($0, to: root.appendingPathComponent("export-first.png")) } ?? 0
        let lastInk = try pdfDocument?.page(at: max(0, pageCount - 1)).map { try renderedInk($0, to: root.appendingPathComponent("export-last.png")) } ?? 0
        report["nativePDFExport"] = ["header": pdfData.starts(with: Data("%PDF-".utf8)), "pageCount": pageCount,
                                     "multiPage": pageCount > 1, "bytes": pdfData.count,
                                     "containsStart": pdfText.contains("내보내기 검증"),
                                     "containsEnd": pdfText.contains("ENDQA9C3A"),
                                     "firstPageInkFraction": firstInk, "lastPageInkFraction": lastInk]

        model.settings.focusMode = true; model.settings.typewriterMode = true
        UserDefaults.standard.synchronize()
        let restored = UserDefaults.standard.data(forKey: "readingSettings")
            .flatMap { try? JSONDecoder().decode(ReadingSettings.self, from: $0) }
        report["editorModeSettingsPersisted"] = restored?.focusMode == true && restored?.typewriterMode == true

        let commandFile = root.appendingPathComponent("command-test.md")
        let base = "# 명령 제목\n\n본문\n"
        let expectations: [String: (String) -> Bool] = [
            "table": { $0.hasPrefix("\n| 제목 | 내용 |\n| :--- | ---: |\n|  |  |\n") },
            "toc": { $0.hasPrefix("## 목차\n\n- [명령 제목](#명령-제목)\n") },
            "footnote": { $0.hasPrefix("[^1]# 명령 제목") && $0.hasSuffix("[^1]: 각주 내용") },
            "frontMatter": { $0.hasPrefix("---\ntitle: 문서 제목\n---\n\n# 명령 제목") },
            "orderedList": { $0.hasPrefix("1. # 명령 제목") },
            "strike": { $0.hasPrefix("~~~~# 명령 제목") },
            "horizontalRule": { $0.hasPrefix("\n---\n# 명령 제목") },
            "mathBlock": { $0.hasPrefix("\n$$\n\n$$\n# 명령 제목") },
        ]
        var commandResults: [String: Bool] = [:]
        for command in ["table", "toc", "footnote", "frontMatter", "orderedList", "strike", "horizontalRule", "mathBlock"] {
            try Data(base.utf8).write(to: commandFile, options: .atomic)
            try await model.resetQAFixture(commandFile)
            model.command(command)
            let source = try await model.bridge.snapshot()["text"] as? String ?? ""
            commandResults[command] = expectations[command]?(source) == true
        }
        report["insertCommands"] = commandResults
    }

    private static func renderedInk(_ page: PDFPage, to url: URL) throws -> Double {
        let image = page.thumbnail(of: NSSize(width: 595, height: 842), for: .mediaBox)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileReadCorruptFile) }
        try png.write(to: url, options: .atomic)
        var ink = 0, samples = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                samples += 1
                if color.alphaComponent > 0.05,
                   color.redComponent < 0.97 || color.greenComponent < 0.97 || color.blueComponent < 0.97 { ink += 1 }
            }
        }
        return samples == 0 ? 0 : Double(ink) / Double(samples)
    }

    private static func workspaceChecks(model: AppModel, root: URL, report: inout [String: Any]) async throws {
        let work = root.appendingPathComponent("Workspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try await model.setQAWorkspace(work)
        model.settings.autosave = false
        let folder = try await model.workspaceFiles.createFolder(root: work, directory: work, name: "자료")
        let file = try await model.workspaceFiles.createDocument(root: work, directory: folder, name: "한글 문서")
        model.searchWorkspaceItem(FileEntry(url: folder, isDirectory: true))
        report["contextSearchUsesSelectedFolder"] = model.folderSearchScope == folder
        model.showFolderSearch()
        report["wholeWorkspaceSearchResetsContextScope"] = model.folderSearchScope == nil
        try Data("# 검색 검증\n\n찾을말 👩🏽‍💻\n".utf8).write(to: file)
        try await model.resetQAFixture(file)
        _ = try await model.bridge.snapshot()
        try await insert("새 입력 ", model: model)
        let renamed = folder.appendingPathComponent("이름 변경.md")
        await model.relocateWorkspaceItem(FileEntry(url: file, isDirectory: false), to: renamed)
        let renamedText = try String(contentsOf: renamed, encoding: .utf8)
        report["workspaceRenameSavesDirtyDocument"] = model.documentURL == renamed && renamedText.hasPrefix("새 입력 ")
        model.command("undo"); _ = try await model.bridge.snapshot()
        report["workspaceRenamePreservesUndo"] = (try await model.bridge.snapshot()["text"] as? String)?.hasPrefix("# 검색 검증") == true
        _ = await model.save()

        let outside = work.appendingPathComponent("연결.md")
        try Data("찾을말\n".utf8).write(to: outside)
        let links = folder.appendingPathComponent("링크.md")
        let before = "[외부](../연결.md)\n[내부](이름%20변경.md)\n"
        try Data(before.utf8).write(to: links)
        let destinationParent = try await model.workspaceFiles.createFolder(root: work, directory: work, name: "새 위치")
        let movedFolder = destinationParent.appendingPathComponent("자료", isDirectory: true)
        await model.relocateWorkspaceItem(FileEntry(url: folder, isDirectory: true), to: movedFolder)
        let movedFile = movedFolder.appendingPathComponent("이름 변경.md")
        report["workspaceFolderMoveRebindsOpenDocument"] = model.documentURL == movedFile && !model.hasConflict
        let after = try String(contentsOf: movedFolder.appendingPathComponent("링크.md"), encoding: .utf8)
        report["workspaceFolderMoveRebasesOnlyExternalRelativeLinks"] = after.contains("../../%EC%97%B0%EA%B2%B0.md") && after.contains("[내부](이름%20변경.md)")
        report["workspaceOtherDocumentsUnchanged"] = try String(contentsOf: outside, encoding: .utf8) == "찾을말\n"

        model.folderQuery = "찾을말"; model.folderReplacement = "바꾼말"; model.showFolderSearch(); model.runFolderSearch()
        for _ in 0..<200 { if !model.folderSearching { break }; try await Task.sleep(for: .milliseconds(25)) }
        guard let found = model.folderSearchReport, found.isComplete, found.files.count == 2 else { throw DocumentError.unavailable }
        report["workspaceSearchFindsNestedDocuments"] = true
        if let file = found.files.first(where: { $0.url == movedFile }), let match = file.matches.first {
            await model.openSearchMatch(file, match: match)
            let snapshot = try await model.bridge.snapshot()
            report["workspaceSearchSelectsMatch"] = snapshot["anchor"] as? Int == match.range.lowerBound && snapshot["head"] as? Int == match.range.upperBound
        }
        model.reviewFolderReplacement()
        guard let review = model.replacementReview else { throw DocumentError.unavailable }
        model.replacementReview = nil
        let applied = await model.applyFolderReplacement(review, selected: Set(review.plan.files.map(\.url)))
        let replacedText = try String(contentsOf: movedFile, encoding: .utf8)
        report["workspaceReviewedReplacement"] = applied?.savedCount == 2 && replacedText.contains("바꾼말")
        report["workspaceReplacementRefreshesEditor"] = (try await model.bridge.snapshot()["text"] as? String)?.contains("바꾼말") == true
        model.folderQuery = "바꾼말"; model.runFolderSearch()
        for _ in 0..<200 { if !model.folderSearching { break }; try await Task.sleep(for: .milliseconds(25)) }
        report["workspaceNewQueryKeepsFreshResults"] = model.folderSearchReport?.files.count == 2

        let partialRoot = work.appendingPathComponent("부분 실패", isDirectory: true)
        try FileManager.default.createDirectory(at: partialRoot, withIntermediateDirectories: true)
        for name in ["a.md", "b.md"] { try Data("부분실패검색어".utf8).write(to: partialRoot.appendingPathComponent(name)) }
        let partialPlan = await FolderSearch.scan(folder: partialRoot, options: .init(query: "부분실패검색어"))
        guard let delayedFile = partialPlan.files.last else { throw DocumentError.unavailable }
        let hold = QAWriteHold(url: delayedFile.url)
        NSFileCoordinator.addFilePresenter(hold)
        defer { hold.release.signal(); NSFileCoordinator.removeFilePresenter(hold) }
        let applying = Task { await FolderSearch.apply(plan: partialPlan.replacementPlan, replacement: "저장된 변경", store: model.store) }
        for _ in 0..<200 { if hold.hasEntered { break }; try await Task.sleep(for: .milliseconds(25)) }
        if hold.hasEntered { try Data("외부 수정 보존".utf8).write(to: delayedFile.url, options: .atomic) }
        hold.release.signal()
        let partialResult = await applying.value
        let externalText = try String(contentsOf: delayedFile.url, encoding: .utf8)
        report["workspacePartialReplaceReportsEachFile"] = hold.hasEntered && partialResult.preflightPassed && partialResult.savedCount == 1
            && partialResult.outcomes.contains(where: { $0.status == .stale }) && externalText == "외부 수정 보존"
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
            let editorRevision = try await web.callAsyncJavaScript("return window.MarkdownHost.snapshot().revision", arguments: [:], in: nil, contentWorld: .page) as? Int ?? -1
            let drainBegan = Date.timeIntervalSinceReferenceDate
            while model.revisionForQA < editorRevision, Date.timeIntervalSinceReferenceDate - drainBegan < 2 { try await Task.sleep(for: .milliseconds(1)) }
            guard model.revisionForQA == editorRevision else { throw DocumentError.invalidChange }
            var bridgeSamples: [Double] = []
            for _ in 0..<12 {
                let expectedRevision = model.revisionForQA + 1
                let began = Date.timeIntervalSinceReferenceDate
                _ = try await web.callAsyncJavaScript("window.MarkdownHost.receive({type:'insert', sessionID:sessionID, documentID:documentID, text:'나'}); return true", arguments: ["sessionID": model.sessionID, "documentID": model.documentID], in: nil, contentWorld: .page)
                while model.revisionForQA < expectedRevision, Date.timeIntervalSinceReferenceDate - began < 2 {
                    try await Task.sleep(for: .milliseconds(1))
                }
                guard model.revisionForQA == expectedRevision else { throw DocumentError.invalidChange }
                bridgeSamples.append((Date.timeIntervalSinceReferenceDate - began) * 1000)
            }
            bridgeSamples.sort()
            report["nativeBridgeInputP95Ms"] = bridgeSamples[11]
            report["nativeBridgeAppliedEdits"] = bridgeSamples.count
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
