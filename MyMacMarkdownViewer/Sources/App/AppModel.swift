import AppKit
import SwiftUI
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import MyMarkdownCore
#endif

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    let access = AccessManager()
    let bridge = EditorBridge()
    let store: FileStore
    let workspaceFiles = WorkspaceFiles()
    let outlineNavigation = OutlineSidebarState()
    @Published var workspaceBusy = false
    @Published var workspaceNotice: String?
    @Published var folderQuery = "" { didSet { if folderQuery != oldValue { invalidateFolderSearch() } } }
    @Published var folderCaseSensitive = false { didSet { if folderCaseSensitive != oldValue { invalidateFolderSearch() } } }
    @Published var folderSearchScope: URL?
    @Published var folderReplacement = ""
    @Published var folderSearching = false
    @Published var folderSearchReport: FolderSearch.ScanReport?
    @Published var replacementReview: FolderReplacementReview?
    private var folderSearchTask: Task<Void, Never>?
    private var searchGeneration = UUID()
    @Published var settings: ReadingSettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "readingSettings") }
            applyAppearance(); sendSettings()
            if settings.autosave != oldValue.autosave { scheduleAutosave() }
        }
    }
    @Published var documentURL: URL?
    @Published var folderURL: URL?
    @Published var isDirty = false
    @Published var isSaving = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasConflict = false
    @Published var sourceMode = false
    @Published var remoteImages = false
    @Published var outline: [OutlineEntry] = []
    @Published var visibleFrom = 0
    @Published var characters = 0
    @Published var words = 0
    @Published var lines = 1
    @Published var rootEntries: [FileEntry] = [] { didSet { fileTreeRowsCache = nil } }
    @Published var children: [String: [FileEntry]] = [:] { didSet { fileTreeRowsCache = nil } }
    @Published var expanded: Set<String> = [] { didSet { fileTreeRowsCache = nil } }
    private var fileTreeRowsCache: [FileTreeRow]?
    var visibleFileRows: [FileTreeRow] {
        if let fileTreeRowsCache { return fileTreeRowsCache }
        let rows = FileTreeProjection.rows(roots: rootEntries, children: children, expanded: expanded)
        fileTreeRowsCache = rows
        return rows
    }
    @Published var indexedFiles: [URL] = []
    @Published var indexing = false
    @Published var quickOpen = false
    @Published var quickQuery = ""
    @Published var sidebarMode = "files"
    @Published var recoveries: [RecoveryRecord] = []
    @Published var showRecovery = false
    @Published var sidebarVisible = true

    private(set) var sessionID = UUID().uuidString
    private(set) var documentID = UUID().uuidString
    private var recoveryID = UUID().uuidString
    private var revision = 0
    private var text = "# 조용한 문서 공간\n\n문서나 폴더를 열어 시작하세요. 읽던 흐름에서 필요한 부분만 자연스럽게 고칠 수 있습니다.\n\n## 읽기와 편집\n\n- **⌘O** 문서 열기 · **⌘⇧O** 폴더 열기\n- **⌘P** 빠른 파일 열기 · **⌘F** 문서 검색\n- **⌘⇧M** 원문 모드 전환\n\n> 기본 테마는 다크 모드입니다. 설정에서 글꼴과 읽기 폭을 조절할 수 있습니다.\n"
    private var codec: DocumentCodec
    private var composing = false
    private var desynchronized = false
    private var transitioning = false
    private var anchor = 0
    private var head = 0
    private var scrollTop = 0.0
    private var autosaveTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var indexTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var externalCheckTask: Task<Void, Never>?
    var revisionForQA: Int { revision }
    private var observation: FileObservation?
    private var folderObservation: FolderObservation?
    private var fileFolderObservation: FolderObservation?
    private var folderGeneration = UUID()
    private var startupDone = false
    private var navigationGeneration = 0
    private var positionTask: Task<Void, Never>?

    init() {
        settings = (UserDefaults.standard.data(forKey: "readingSettings").flatMap { try? JSONDecoder().decode(ReadingSettings.self, from: $0) }) ?? ReadingSettings()
        let args = ProcessInfo.processInfo.arguments
        let support: URL
        if let index = args.firstIndex(of: "--qa-root"), args.indices.contains(index + 1) {
            support = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        } else {
            support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MyMarkdownViewer", isDirectory: true)
        }
        store = FileStore(supportURL: support)
        codec = try! DocumentCodec(data: Data(text.utf8))
        bridge.model = self
        applyAppearance()
    }

    var resolvedTheme: String {
        switch settings.theme {
        case .dark: "dark"
        case .night: "night"
        case .light: "light"
        case .system: NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
        }
    }
    var usesDarkAppearance: Bool { resolvedTheme != "light" }
    var canvasNSColor: NSColor {
        switch resolvedTheme {
        case "night": NSColor(srgbRed: 55 / 255, green: 59 / 255, blue: 64 / 255, alpha: 1)
        case "light": NSColor(red: 0.98, green: 0.976, blue: 0.965, alpha: 1)
        default: NSColor(red: 0.098, green: 0.106, blue: 0.118, alpha: 1)
        }
    }
    var nightChromeNSColor: NSColor { NSColor(srgbRed: 48 / 255, green: 52 / 255, blue: 58 / 255, alpha: 1) }
    var title: String { documentURL?.lastPathComponent ?? "새 문서" }
    private var markdownContentTypes: [UTType] {
        [UTType(filenameExtension: "md"), UTType(filenameExtension: "markdown")].compactMap { $0 }
    }
    var status: String {
        if isLoading { return "문서 불러오는 중…" }
        if isSaving { return "저장 중…" }
        if hasConflict { return "외부 변경 확인 필요" }
        if isDirty { return documentURL == nil ? "저장 위치 미지정" : "미저장 변경" }
        return documentURL == nil ? "로컬 Markdown" : "저장됨"
    }
    var currentHeading: Int? { outline.last(where: { $0.from <= visibleFrom })?.from ?? outline.first?.from }
    var settingsPayload: [String: Any] {
        ["theme": resolvedTheme, "fontSize": settings.fontSize, "lineHeight": settings.lineHeight,
         "contentWidth": settings.contentWidth, "fontFamily": settings.fontFamily, "remoteImages": remoteImages,
         "focusMode": settings.focusMode, "typewriterMode": settings.typewriterMode]
    }

    func applyAppearance() {
        NSApp?.appearance = settings.theme == .system ? nil : NSAppearance(named: usesDarkAppearance ? .darkAqua : .aqua)
    }
    func sendSettings() { bridge.send(["type": "settings", "settings": settingsPayload]) }
    func systemAppearanceChanged() { if settings.theme == .system { objectWillChange.send(); sendSettings() } }
    private func message(_ type: String, _ values: [String: Any] = [:]) -> [String: Any] {
        ["type": type, "documentID": documentID, "sessionID": sessionID, "revision": revision].merging(values) { _, new in new }
    }
    func command(_ name: String) { bridge.send(message("command", ["command": name])) }
    func jump(_ from: Int) { bridge.send(message("jump", ["from": from])) }
    func toggleRemoteImages() { remoteImages.toggle(); sendSettings() }
    func showError(_ error: Error) { errorMessage = error.localizedDescription }

    private func preparedExportHTML() async throws -> String {
        try await syncSnapshot()
        guard !composing else { throw CocoaError(.userCancelled) }
        let exportSession = sessionID, exportRevision = revision
        let html = try await bridge.exportHTML()
        let confirmation = try await bridge.snapshot()
        guard exportSession == sessionID,
              confirmation["sessionID"] as? String == exportSession,
              confirmation["revision"] as? Int == exportRevision,
              confirmation["composing"] as? Bool != true else { throw DocumentError.invalidChange }
        return html
    }

    private func validateExportDestination(_ url: URL) throws {
        guard let documentURL else { return }
        let source = documentURL.standardizedFileURL.resolvingSymlinksInPath()
        let destination = url.standardizedFileURL.resolvingSymlinksInPath()
        guard source.path.compare(destination.path, options: [.caseInsensitive, .literal]) != .orderedSame else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
    }

    func exportHTML() async {
        do {
            let html = try await preparedExportHTML()
            let exportSession = sessionID, exportRevision = revision
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.html]
            panel.nameFieldStringValue = (documentURL?.deletingPathExtension().lastPathComponent ?? "문서") + ".html"
            panel.directoryURL = documentURL?.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try validateExportDestination(url)
            guard exportSession == sessionID, exportRevision == revision, !composing else { throw DocumentError.invalidChange }
            try Data(html.utf8).write(to: url, options: .atomic)
        } catch CocoaError.userCancelled {} catch { showError(error) }
    }

    func exportPDF() async {
        do {
            let html = try await preparedExportHTML()
            let exportSession = sessionID, exportRevision = revision
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = (documentURL?.deletingPathExtension().lastPathComponent ?? "문서") + ".pdf"
            panel.directoryURL = documentURL?.deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try validateExportDestination(url)
            guard exportSession == sessionID, exportRevision == revision, !composing else { throw DocumentError.invalidChange }
            try await HTMLPrintRenderer().savePDF(html: html, to: url)
        } catch CocoaError.userCancelled {} catch { showError(error) }
    }

    func printDocument() async {
        do { try await HTMLPrintRenderer().printDocument(html: try await preparedExportHTML()) }
        catch CocoaError.userCancelled {} catch { showError(error) }
    }

    func editorReady() {
        sendDocument()
        guard !startupDone else { return }
        startupDone = true
        let generation = navigationGeneration
        Task {
            do { recoveries = try await store.recoveries(); showRecovery = !recoveries.isEmpty } catch { showError(error) }
            let args = ProcessInfo.processInfo.arguments
            let explicitURL = args.firstIndex(of: "--open").flatMap { index in
                args.indices.contains(index + 1) ? URL(fileURLWithPath: args[index + 1]) : nil
            }
            await restoreLastSession(generation: generation, restoreDocument: explicitURL == nil)
            if let explicitURL, navigationGeneration == generation { await open(explicitURL) }
            if args.contains("--qa") { await runAppQA() }
            if args.contains("--qa-session") { await SessionQA.run(model: self) }
        }
    }
    private func restoreLastSession(generation: Int, restoreDocument: Bool) async {
        guard navigationGeneration == generation, documentURL == nil, !isDirty else { return }
        var notices: [String] = []
        if let path = UserDefaults.standard.string(forKey: "lastFolder") {
            if let url = access.restore(path) {
                do {
                    _ = try await Task.detached { try FolderScanner.children(of: url) }.value
                    guard navigationGeneration == generation else { return }
                    await setFolder(url)
                } catch { notices.append("마지막 폴더를 열 수 없습니다. 삭제되었거나 접근 권한이 바뀌었을 수 있습니다. 폴더를 다시 선택해 주세요.") }
            } else { notices.append("마지막 폴더의 접근 권한을 복원하지 못했습니다. 폴더를 다시 선택해 주세요.") }
        }
        guard navigationGeneration == generation, !transitioning, !isDirty else { return }
        if restoreDocument, let path = UserDefaults.standard.string(forKey: "lastDocument") {
            let fallback = URL(fileURLWithPath: path)
            if let url = access.restore(path) ?? (access.canRead(fallback) ? fallback : nil) {
                do {
                    let disk = try await store.read(url)
                    guard navigationGeneration == generation, !transitioning, !isDirty else { return }
                    if url.path != path, let value = UserDefaults.standard.dictionary(forKey: "position:\(path)") {
                        UserDefaults.standard.set(value, forKey: "position:\(url.path)")
                    }
                    resetDocument(url: url, codec: disk.codec)
                } catch { notices.append("마지막 문서 ‘\(fallback.lastPathComponent)’를 열 수 없습니다. 삭제·이동되었거나 접근 권한이 바뀌었을 수 있습니다. 문서를 다시 선택해 주세요.") }
            } else { notices.append("마지막 문서의 접근 권한을 복원하지 못했습니다. 문서를 다시 선택해 주세요.") }
        }
        if navigationGeneration == generation, !notices.isEmpty { errorMessage = notices.joined(separator: "\n") }
    }
    private func sendDocument() {
        bridge.send(message("open", ["text": text, "baseURL": documentURL?.deletingLastPathComponent().absoluteString ?? "",
                                    "settings": settingsPayload, "anchor": anchor, "head": head, "scrollTop": scrollTop, "sourceMode": sourceMode]))
    }
    func webProcessTerminated() {
        composing = false; desynchronized = false; sessionID = UUID().uuidString
        errorMessage = "편집 화면을 다시 불러왔습니다. 마지막으로 전달된 편집 내용은 유지됩니다."
        scheduleRecovery()
    }

    func receive(_ body: [String: Any]) {
        guard body["sessionID"] as? String == sessionID, body["documentID"] as? String == documentID,
              let type = body["type"] as? String else { return }
        switch type {
        case "changed":
            guard let base = body["baseRevision"] as? Int, let next = body["revision"] as? Int,
                  base == revision, next == revision + 1, let values = body["changes"] as? [[String: Any]] else {
                desynchronized = true; autosaveTask?.cancel(); errorMessage = DocumentError.invalidChange.localizedDescription; return
            }
            do {
                let changes = try JSONDecoder().decode([TextChange].self, from: JSONSerialization.data(withJSONObject: values))
                text = try TextChange.apply(changes, to: text); revision = next
                navigationGeneration += 1
                composing = body["composing"] as? Bool ?? false
                let dirty = text != codec.originalText
                if isDirty != dirty { isDirty = dirty }
                scheduleRecovery(); scheduleAutosave()
            } catch { desynchronized = true; showError(error) }
        case "metadata":
            guard body["revision"] as? Int == revision else { return }
            let nextOutline: [OutlineEntry] = (body["headings"] as? [[String: Any]] ?? []).compactMap {
                guard let title = $0["title"] as? String, let level = $0["level"] as? Int, let from = $0["from"] as? Int else { return nil }
                return OutlineEntry(title: title, level: level, from: from)
            }
            if outline != nextOutline { outline = nextOutline }
            characters = body["characters"] as? Int ?? 0; words = body["words"] as? Int ?? 0; lines = body["lines"] as? Int ?? 1
        case "position":
            anchor = body["anchor"] as? Int ?? 0; head = body["head"] as? Int ?? anchor
            scrollTop = body["scrollTop"] as? Double ?? 0
            schedulePositionPersistence()
            let nextVisible = body["visibleFrom"] as? Int ?? 0
            if visibleFrom != nextVisible { visibleFrom = nextVisible }
        case "composition": composing = body["active"] as? Bool ?? false; scheduleRecovery(); scheduleAutosave()
        case "save": Task { _ = await save() }
        case "sourceMode": sourceMode = body["enabled"] as? Bool ?? false
        case "remoteImages": remoteImages = true; sendSettings()
        case "grantFolder": chooseAssetFolder()
        case "openLink": if let href = body["href"] as? String { openLink(href) }
        case "insertImageData":
            if let name = body["name"] as? String, let raw = body["data"] as? String, raw.utf8.count <= 28 * 1024 * 1024, let data = Data(base64Encoded: raw) {
                Task { await importImage(data: data, name: name) }
            }
        case "error": errorMessage = body["message"] as? String
        default: break
        }
        NSApp?.mainWindow?.isDocumentEdited = isDirty
    }

    private func syncSnapshot() async throws {
        let snapshot = try await bridge.snapshot()
        guard snapshot["sessionID"] as? String == sessionID, let next = snapshot["revision"] as? Int,
              let source = snapshot["text"] as? String else { throw DocumentError.invalidChange }
        if next >= revision { text = source; revision = next; desynchronized = false; isDirty = text != codec.originalText }
        composing = snapshot["composing"] as? Bool ?? false
        anchor = snapshot["anchor"] as? Int ?? anchor; head = snapshot["head"] as? Int ?? head
        scrollTop = snapshot["scrollTop"] as? Double ?? scrollTop
    }

    private var recoveryRecord: RecoveryRecord { RecoveryRecord(id: recoveryID, path: documentURL?.path, text: text, codec: codec, revision: revision) }
    private func finishRecoveryTask() async {
        let pending = recoveryTask
        recoveryTask = nil
        pending?.cancel()
        // Cancellation cannot retract a write already submitted to FileStore.
        // Join it before deleting or replacing that checkpoint.
        await pending?.value
    }
    private func scheduleRecovery() {
        let previous = recoveryTask
        previous?.cancel()
        let current = sessionID
        recoveryTask = Task {
            await previous?.value
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard current == sessionID, !composing else { return }
                if isDirty { try await store.writeRecovery(recoveryRecord) }
                else { try await store.removeRecovery(recoveryID) }
            } catch is CancellationError {} catch { showError(error) }
        }
    }
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard settings.autosave, documentURL != nil, isDirty, !hasConflict, !composing, !desynchronized, !transitioning else { return }
        autosaveTask = Task {
            do { try await Task.sleep(for: .seconds(1)); _ = await save(automatic: true) }
            catch {}
        }
    }

    func save(automatic: Bool = false, workspace: Bool = false) async -> Bool {
        guard !workspaceBusy || workspace else { return false }
        while isSaving { try? await Task.sleep(for: .milliseconds(30)); if Task.isCancelled { return false } }
        guard !hasConflict, !desynchronized else { return false }
        if documentURL == nil { return automatic ? false : await saveAs() }
        do {
            try await syncSnapshot()
            guard !composing else { return false }
            guard isDirty else { return true }
            let current = sessionID, savingText = text, savingCodec = codec, savingURL = documentURL!
            isSaving = true
            defer { isSaving = false }
            await finishRecoveryTask()
            try await store.writeRecovery(recoveryRecord)
            let saved = try await store.save(savingURL, text: savingText, codec: savingCodec, expectedHash: DocumentCodec.hash(savingCodec.originalData))
            guard current == sessionID else { return false }
            codec = saved.codec; isDirty = text != codec.originalText
            if isDirty { try await store.writeRecovery(recoveryRecord); scheduleAutosave() }
            else { try await store.removeRecovery(recoveryID) }
            errorMessage = nil
            bridge.send(message("saved"))
            return true
        } catch {
            if let error = error as? DocumentError, error == .conflict || error == .deleted { hasConflict = true }
            showError(error); return false
        }
    }

    func saveAs() async -> Bool {
        guard !isSaving, !workspaceBusy else { return false }
        do { try await syncSnapshot() } catch { showError(error); return false }
        guard !composing else { return false }
        let panel = NSSavePanel(); panel.allowedContentTypes = markdownContentTypes
        panel.nameFieldStringValue = documentURL?.lastPathComponent ?? "새 문서.md"
        panel.directoryURL = documentURL?.deletingLastPathComponent() ?? folderURL
        guard panel.runModal() == .OK, let target = panel.url else { return false }
        access.grant(target)
        isSaving = true; autosaveTask?.cancel(); recoveryTask?.cancel()
        bridge.send(message("lock", ["locked": true]))
        defer { isSaving = false; bridge.send(message("lock", ["locked": false])) }
        do {
            let snapshot = try await bridge.snapshot(newBase: target.deletingLastPathComponent().absoluteString)
            guard snapshot["sessionID"] as? String == sessionID, let rebased = snapshot["text"] as? String else { throw DocumentError.invalidChange }
            let exists = FileManager.default.fileExists(atPath: target.path)
            let expected = exists ? try await store.read(target).hash : nil
            if target == documentURL, expected != DocumentCodec.hash(codec.originalData) { throw DocumentError.conflict }
            await finishRecoveryTask()
            try await store.writeRecovery(recoveryRecord)
            let result = try await store.save(target, text: rebased, codec: codec, expectedHash: expected)
            persistPosition()
            documentURL = target; documentID = target.path; text = rebased; codec = result.codec
            sessionID = UUID().uuidString; revision = 0; isDirty = false; hasConflict = false; desynchronized = false
            try await store.removeRecovery(recoveryID); recoveryID = UUID().uuidString
            errorMessage = nil; sendDocument(); observeDocument(); NSDocumentController.shared.noteNewRecentDocumentURL(target)
            rememberDocument(); persistPosition()
            return true
        } catch { showError(error); return false }
    }

    private func prepareToLeave() async -> Bool {
        if bridge.isReady { do { try await syncSnapshot() } catch { showError(error); return false } }
        if composing { return false }
        while isSaving { try? await Task.sleep(for: .milliseconds(30)) }
        await finishRecoveryTask()
        guard isDirty else { try? await store.removeRecovery(recoveryID); persistPosition(); return true }
        if settings.autosave, documentURL != nil, !hasConflict, !desynchronized, await save() { persistPosition(); return true }
        let alert = NSAlert(); alert.messageText = "변경 내용을 저장할까요?"; alert.informativeText = title
        alert.addButton(withTitle: hasConflict ? "편집본 별도 저장" : "저장"); alert.addButton(withTitle: "취소"); alert.addButton(withTitle: "변경 버리기")
        switch alert.runModal() {
        case .alertFirstButtonReturn: let saved = hasConflict ? await saveAs() : await save(); if saved { persistPosition() }; return saved
        case .alertThirdButtonReturn:
            await finishRecoveryTask(); autosaveTask?.cancel()
            do { try await store.removeRecovery(recoveryID) } catch { showError(error); return false }
            if ProcessInfo.processInfo.arguments.contains("--qa") {
                let remaining = (try? await store.recoveries())?.contains { $0.id == recoveryID } ?? true
                FileHandle.standardError.write(Data("QA discard removed checkpoint: \(!remaining)\n".utf8))
            }
            persistPosition()
            // Discard ends the editing session too. Otherwise a late editor
            // message can recreate its checkpoint after the user discarded it.
            resetDocument(url: documentURL, codec: codec)
            return true
        default: return false
        }
    }

    func canClose() async -> Bool {
        guard !transitioning else { return false }
        transitioning = true; defer { transitioning = false }
        bridge.send(message("lock", ["locked": true])); defer { bridge.send(message("lock", ["locked": false])) }
        return await prepareToLeave()
    }

    func newDocument() async {
        navigationGeneration += 1
        guard !transitioning else { return }; transitioning = true; defer { transitioning = false }
        bridge.send(message("lock", ["locked": true])); defer { bridge.send(message("lock", ["locked": false])) }
        guard await prepareToLeave() else { return }
        resetDocument(url: nil, codec: try! DocumentCodec(data: Data()))
    }
    func chooseDocument() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = markdownContentTypes; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { Task { await open(url) } }
    }
    func open(_ url: URL) async {
        navigationGeneration += 1
        guard !transitioning, url != documentURL else { return }
        transitioning = true; defer { transitioning = false }
        bridge.send(message("lock", ["locked": true])); defer { bridge.send(message("lock", ["locked": false])) }
        guard await prepareToLeave() else { return }
        isLoading = true; defer { isLoading = false }
        access.grant(url)
        do { let disk = try await store.read(url); resetDocument(url: url, codec: disk.codec); NSDocumentController.shared.noteNewRecentDocumentURL(url) }
        catch { showError(error) }
    }
    private func resetDocument(url: URL?, codec: DocumentCodec) {
        autosaveTask?.cancel(); recoveryTask?.cancel(); positionTask?.cancel()
        documentURL = url; documentID = url?.path ?? UUID().uuidString; sessionID = UUID().uuidString; recoveryID = UUID().uuidString
        self.codec = codec; text = codec.originalText; revision = 0; isDirty = false; hasConflict = false; desynchronized = false; composing = false
        outlineNavigation.reset()
        errorMessage = nil; remoteImages = false; sourceMode = false; outline = []; anchor = 0; head = 0; scrollTop = 0
        access.retainAccess(for: [url, folderURL].compactMap { $0 })
        restorePosition(); sendDocument(); observeDocument()
        rememberDocument()
    }

    func reloadFromDisk() async {
        guard let documentURL else { return }
        if isDirty {
            let alert = NSAlert(); alert.messageText = "디스크 버전으로 바꿀까요?"; alert.informativeText = "현재 편집본은 복구 목록에 보관합니다."
            alert.addButton(withTitle: "디스크 버전 열기"); alert.addButton(withTitle: "취소")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            do { try await store.writeRecovery(recoveryRecord) } catch { showError(error); return }
        }
        do { let disk = try await store.read(documentURL); persistPosition(); resetDocument(url: documentURL, codec: disk.codec) }
        catch { showError(error) }
    }
    private func observeDocument() {
        externalCheckTask?.cancel()
        observation?.stop(); observation = nil; fileFolderObservation?.stop(); fileFolderObservation = nil
        guard let documentURL else { return }
        observation = FileObservation(url: documentURL) { [weak self] in Task { @MainActor in self?.scheduleExternalCheck() } }
        fileFolderObservation = FolderObservation(url: documentURL.deletingLastPathComponent()) { [weak self] in Task { self?.scheduleExternalCheck() } }
    }
    private func scheduleExternalCheck() {
        externalCheckTask?.cancel()
        let current = sessionID
        externalCheckTask = Task {
            do {
                repeat {
                    try await Task.sleep(for: .milliseconds(250))
                    guard current == sessionID else { return }
                } while isSaving || transitioning || isLoading
                await checkExternalChange()
            } catch is CancellationError {} catch { showError(error) }
        }
    }
    func checkExternalChange() async {
        guard let url = documentURL, !isSaving, !transitioning, !isLoading else { return }
        let current = sessionID
        do {
            let disk = try await store.read(url)
            guard current == sessionID, !isSaving, !transitioning else { return }
            guard disk.hash != DocumentCodec.hash(codec.originalData) else { return }
            if isDirty || composing { hasConflict = true; autosaveTask?.cancel(); errorMessage = DocumentError.conflict.localizedDescription }
            else { persistPosition(); resetDocument(url: url, codec: disk.codec) }
        } catch {
            guard current == sessionID, !isSaving else { return }
            hasConflict = true; autosaveTask?.cancel(); showError(error)
        }
    }
    func didBecomeActive() { Task { await checkExternalChange(); if folderURL != nil { refreshFolder() } }; systemAppearanceChanged() }

    func chooseFolder() {
        guard !workspaceBusy else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.prompt = "폴더 열기"
        if panel.runModal() == .OK, let url = panel.url { navigationGeneration += 1; Task { await setFolder(url) } }
    }
    func chooseAssetFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.directoryURL = documentURL?.deletingLastPathComponent()
        panel.message = "문서가 참조하는 이미지가 있는 폴더를 선택하세요."
        if panel.runModal() == .OK, let url = panel.url { access.grant(url); sendSettings() }
    }
    private func setFolder(_ url: URL) async {
        folderSearchScope = nil
        folderSearchTask?.cancel(); folderSearchReport = nil; replacementReview = nil
        searchGeneration = UUID(); folderSearching = false
        folderObservation?.stop(); indexTask?.cancel(); refreshTask?.cancel()
        access.grant(url); folderURL = url; folderGeneration = UUID(); children = [:]; rootEntries = []; indexedFiles = []
        UserDefaults.standard.set(url.path, forKey: "lastFolder")
        expanded = Set(UserDefaults.standard.stringArray(forKey: "expanded:\(url.path)") ?? [])
        folderObservation = FolderObservation(url: url) { [weak self] in self?.refreshFolder() }
        refreshFolder()
    }
    func refreshFolder() {
        refreshTask?.cancel(); indexTask?.cancel()
        guard let folderURL else { return }
        let generation = folderGeneration, expandedPaths = expanded
        refreshTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(180))
                let result = try await Task.detached {
                    var children: [String: [FileEntry]] = [:]
                    for path in expandedPaths where path.hasPrefix(folderURL.path + "/") { children[path] = try? FolderScanner.children(of: URL(fileURLWithPath: path)) }
                    return (try FolderScanner.children(of: folderURL), children)
                }.value
                guard generation == folderGeneration, !Task.isCancelled else { return }
                rootEntries = result.0; children = result.1; startIndex()
            } catch is CancellationError {} catch { showError(error) }
        }
    }
    private func startIndex() {
        guard let folderURL else { return }; let generation = folderGeneration; indexing = true
        indexTask = Task {
            let worker = Task.detached(priority: .utility) { FolderScanner.index(folderURL) }
            let files = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard generation == folderGeneration, !Task.isCancelled else { return }; indexedFiles = files; indexing = false
        }
    }
    func toggleFolder(_ entry: FileEntry) {
        if expanded.contains(entry.id) { expanded.remove(entry.id) }
        else {
            expanded.insert(entry.id)
            let generation = folderGeneration
            Task {
                do { let entries = try await Task.detached { try FolderScanner.children(of: entry.url) }.value
                    if generation == folderGeneration { children[entry.id] = entries }
                } catch { showError(error) }
            }
        }
        if let folderURL { UserDefaults.standard.set(Array(expanded), forKey: "expanded:\(folderURL.path)") }
    }
    var filteredFiles: [URL] {
        let query = quickQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(indexedFiles.filter { query.isEmpty || relativePath($0).localizedCaseInsensitiveContains(query) }.prefix(100))
    }
    func relativePath(_ url: URL) -> String { guard let folderURL, url.path.hasPrefix(folderURL.path + "/") else { return url.lastPathComponent }; return String(url.path.dropFirst(folderURL.path.count + 1)) }
    func reveal(_ url: URL? = nil) { if let url = url ?? documentURL ?? folderURL { NSWorkspace.shared.activateFileViewerSelecting([url]) } }

    func chooseImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .gif, .webP, .tiff, .heic]
        if panel.runModal() == .OK, let url = panel.url { Task { do { await importImage(data: try Data(contentsOf: url), name: url.lastPathComponent) } catch { showError(error) } } }
    }
    private func importImage(data: Data, name: String) async {
        guard data.count <= 20 * 1024 * 1024, NSImage(data: data) != nil else { errorMessage = "지원하는 20MB 이하 이미지 파일을 선택해 주세요."; return }
        if documentURL == nil, !(await saveAs()) { return }
        guard let documentURL else { return }
        let current = sessionID, directory = documentURL.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true)
        do {
            let parent = documentURL.deletingLastPathComponent()
            if !access.canRead(parent) { chooseAssetFolder() }
            guard access.canRead(parent) else { throw CocoaError(.fileWriteNoPermission) }
            let canonicalParent = parent.resolvingSymlinksInPath().standardizedFileURL.path
            guard directory.resolvingSymlinksInPath().path.hasPrefix(canonicalParent + "/") else { throw DocumentError.unsafePath }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let rawName = (name as NSString).lastPathComponent
            let fileName = rawName.isEmpty ? "image.png" : rawName
            let base = (fileName as NSString).deletingPathExtension, ext = (fileName as NSString).pathExtension
            var destination = directory.appendingPathComponent(fileName), count = 1
            while FileManager.default.fileExists(atPath: destination.path) { destination = directory.appendingPathComponent("\(base)-\(count).\(ext)"); count += 1 }
            try data.write(to: destination, options: .withoutOverwriting)
            guard current == sessionID else { return }
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "()[]#?"))
            let relative = "assets/" + (destination.lastPathComponent.addingPercentEncoding(withAllowedCharacters: allowed) ?? destination.lastPathComponent)
            bridge.send(message("insert", ["text": "![이미지](\(relative))"]))
        } catch { showError(error) }
    }
    private func openLink(_ href: String) {
        if href.hasPrefix("#") {
            let fragment = String(href.dropFirst()).removingPercentEncoding ?? String(href.dropFirst())
            if let heading = outline.first(where: { $0.title.lowercased().replacingOccurrences(of: " ", with: "-") == fragment || $0.title == fragment }) { jump(heading.from) }; return
        }
        guard let url = URL(string: href, relativeTo: documentURL?.deletingLastPathComponent())?.absoluteURL else { return }
        if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        else if url.isFileURL, MarkdownFileSupport.isMarkdownFile(url), access.canRead(url) { Task { await open(url) } }
    }

    private func persistPosition() {
        positionTask?.cancel()
        guard let documentURL else { return }
        UserDefaults.standard.set(["anchor": Double(anchor), "head": Double(head), "scrollTop": scrollTop], forKey: "position:\(documentURL.path)")
    }
    private func rememberDocument() {
        if let documentURL { UserDefaults.standard.set(documentURL.path, forKey: "lastDocument") }
        else { UserDefaults.standard.removeObject(forKey: "lastDocument") }
    }
    private func schedulePositionPersistence() {
        guard documentURL != nil else { return }
        positionTask?.cancel()
        let current = sessionID
        positionTask = Task {
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            guard current == sessionID else { return }
            persistPosition()
        }
    }
    func persistReadingPosition() { persistPosition() }
    private func restorePosition() {
        guard let documentURL, let values = UserDefaults.standard.dictionary(forKey: "position:\(documentURL.path)") as? [String: Double] else { return }
        let value = ReadingPosition(values: values, textLength: text.utf16.count)
        anchor = value.anchor; head = value.head; scrollTop = value.scrollTop
    }
    func restore(_ record: RecoveryRecord) async {
        navigationGeneration += 1
        guard await prepareToLeave() else { return }
        let url = record.path.flatMap { access.restore($0) }
        resetDocument(url: url, codec: record.codec)
        text = record.text; revision = 0; recoveryID = record.id; isDirty = text != codec.originalText
        // Recovery never resumes automatic writes until the disk baseline has been checked.
        hasConflict = url != nil; sendDocument(); showRecovery = false
        if let url, let disk = try? await store.read(url), disk.hash == DocumentCodec.hash(codec.originalData) { hasConflict = false; scheduleAutosave() }
    }
    func openRecoveryList() { Task { do { recoveries = try await store.recoveries(); showRecovery = true } catch { showError(error) } } }

    func runAppQA() async {
        await AppQA.run(model: self)
    }

    func resetQAFixture(_ url: URL) async throws {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--qa") || args.contains("--qa-session"), let index = args.firstIndex(of: "--qa-root"), args.indices.contains(index + 1),
              url.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: args[index + 1]).standardizedFileURL.path + "/") else {
            throw DocumentError.unsafePath
        }
        access.grant(url)
        let disk = try await store.read(url)
        resetDocument(url: url, codec: disk.codec)
    }
}

struct FolderReplacementReview: Identifiable {
    let id = UUID()
    let root: URL
    let query: String
    let replacement: String
    let plan: FolderSearch.ReplacementPlan
}

extension AppModel {
    private func requestedName(title: String, initial: String) -> String? {
        let alert = NSAlert(); alert.messageText = title
        let field = NSTextField(string: initial); field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "확인"); alert.addButton(withTitle: "취소")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    func createWorkspaceItem(in directory: URL?, folder: Bool) {
        guard !workspaceBusy, let root = folderURL, let directory = directory ?? folderURL,
              let name = requestedName(title: folder ? "새 폴더" : "새 Markdown 문서", initial: folder ? "새 폴더" : "새 문서.md") else { return }
        Task {
            workspaceBusy = true
            do {
                let result = try await (folder
                    ? workspaceFiles.createFolder(root: root, directory: directory, name: name)
                    : workspaceFiles.createDocument(root: root, directory: directory, name: name))
                expanded.insert(directory.path); refreshFolder(); invalidateFolderSearch()
                workspaceBusy = false
                if !folder { await open(result) }
            } catch { workspaceBusy = false; showError(error) }
        }
    }

    func openWorkspaceItem(_ entry: FileEntry) {
        if entry.isDirectory { expanded.insert(entry.id); refreshFolder() }
        else { Task { await open(entry.url) } }
    }

    func searchWorkspaceItem(_ entry: FileEntry) {
        showFolderSearch(scope: entry.isDirectory ? entry.url : entry.url.deletingLastPathComponent())
    }

    func clearFolderSearchScope() {
        invalidateFolderSearch(); replacementReview = nil; folderSearchScope = nil
    }

    func copyWorkspacePath(_ entry: FileEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.url.path, forType: .string)
    }

    func showWorkspaceInfo(_ entry: FileEntry) {
        do {
            let values = try entry.url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .isDirectoryKey])
            let alert = NSAlert(); alert.messageText = entry.name
            var lines = ["종류: " + (values.isDirectory == true ? "폴더" : "Markdown 문서"), "위치: " + entry.url.path]
            if values.isDirectory != true, let size = values.fileSize { lines.append("크기: " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) }
            if let date = values.creationDate { lines.append("생성: " + date.formatted()) }
            if let date = values.contentModificationDate { lines.append("수정: " + date.formatted()) }
            alert.informativeText = lines.joined(separator: "\n\n")
            alert.addButton(withTitle: "닫기"); alert.runModal()
        } catch { showError(error) }
    }

    func duplicateWorkspaceItem(_ entry: FileEntry) {
        Task {
            guard let root = folderURL, await beginWorkspaceChange() else { return }
            defer { endWorkspaceChange() }
            guard await saveWorkspaceDocumentIfNeeded(in: entry.url) else { return }
            do {
                let result = try await workspaceFiles.duplicate(root: root, source: entry.url)
                expanded.insert(result.deletingLastPathComponent().path)
                refreshFolder(); invalidateFolderSearch()
                workspaceNotice = "\(result.lastPathComponent)을(를) 만들었습니다."
            } catch { showError(error) }
        }
    }

    func renameWorkspaceItem(_ entry: FileEntry) {
        guard !workspaceBusy, let name = requestedName(title: "이름 변경", initial: entry.name) else { return }
        // Validate a single component before constructing a URL (which would normalize ../).
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              ![".", ".."].contains(name), !name.contains("/"), !name.contains("\0") else {
            showError(WorkspaceFileError.invalidName); return
        }
        let resolvedName = !entry.isDirectory && !MarkdownFileSupport.isMarkdownFile(URL(fileURLWithPath: name)) ? name + ".md" : name
        Task { await relocateWorkspaceItem(entry, to: entry.url.deletingLastPathComponent().appendingPathComponent(resolvedName, isDirectory: entry.isDirectory)) }
    }

    func chooseWorkspaceDestination(_ entry: FileEntry) {
        guard !workspaceBusy else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.directoryURL = folderURL; panel.prompt = "여기로 이동"
        panel.message = "현재 작업 폴더 안의 목적지를 선택하세요. 이동한 문서의 상대 링크를 보정합니다. 다른 문서에서 이 항목으로 연결한 링크는 바꾸지 않습니다."
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        Task { await relocateWorkspaceItem(entry, to: directory.appendingPathComponent(entry.name, isDirectory: entry.isDirectory)) }
    }

    private func isInside(_ url: URL, _ parent: URL) -> Bool {
        let path = url.standardizedFileURL.path, root = parent.standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }

    private func beginWorkspaceChange() async -> Bool {
        guard !workspaceBusy, !transitioning else { return false }
        workspaceBusy = true; transitioning = true; autosaveTask?.cancel()
        bridge.send(message("lock", ["locked": true]))
        do {
            try await syncSnapshot()
            guard !composing else { throw DocumentError.unavailable }
            return true
        } catch { showError(error); endWorkspaceChange(); return false }
    }

    private func endWorkspaceChange() {
        bridge.send(message("lock", ["locked": false]))
        transitioning = false; workspaceBusy = false; scheduleAutosave()
    }

    private func saveWorkspaceDocumentIfNeeded(in root: URL) async -> Bool {
        guard let documentURL, isInside(documentURL, root) else { return true }
        if hasConflict || desynchronized { showError(DocumentError.conflict); return false }
        if !isDirty { return true }
        return await save(workspace: true)
    }

    func relocateWorkspaceItem(_ entry: FileEntry, to destination: URL) async {
        guard let root = folderURL, destination != entry.url, await beginWorkspaceChange() else { return }
        defer { endWorkspaceChange() }
        guard await saveWorkspaceDocumentIfNeeded(in: entry.url) else { return }
        let currentURL = documentURL
        let currentMoved = currentURL.map { isInside($0, entry.url) } ?? false
        var didMove = false
        var recoveryIDs: [String] = []
        do {
            let files = try await workspaceFiles.markdownDocuments(root: root, source: entry.url)
            var changes: [(DiskDocument, URL, String, String)] = []
            for file in files {
                let disk = try await store.read(file)
                let target = URL(fileURLWithPath: destination.path + file.path.dropFirst(entry.url.path.count))
                let rebased = try await bridge.rebaseMoved(disk.codec.originalText, oldBase: file.deletingLastPathComponent(),
                    newBase: target.deletingLastPathComponent(), source: entry.url, destination: destination, directory: entry.isDirectory)
                let id = UUID().uuidString
                changes.append((disk, target, rebased, id))
            }
            // Preflight every document before any relocation, then retain originals for interrupted rebasing.
            for (disk, _, _, _) in changes {
                guard try await store.read(disk.url).hash == disk.hash else { throw DocumentError.conflict }
            }
            for (disk, target, rebased, id) in changes where rebased != disk.codec.originalText {
                try await store.writeRecovery(RecoveryRecord(id: id, path: target.path, text: disk.codec.originalText, codec: disk.codec, revision: 0))
                recoveryIDs.append(id)
            }
            _ = try await workspaceFiles.move(root: root, source: entry.url, destination: destination)
            didMove = true
            var failures: [String] = []
            for (disk, target, rebased, id) in changes where rebased != disk.codec.originalText {
                do {
                    _ = try await workspaceFiles.markdownDocuments(root: root, source: target)
                    _ = try await store.save(target, text: rebased, codec: disk.codec, expectedHash: disk.hash)
                    try await store.removeRecovery(id); recoveryIDs.removeAll { $0 == id }
                } catch { failures.append("\(target.lastPathComponent): \(error.localizedDescription)") }
            }
            if currentMoved, let currentURL {
                let target = URL(fileURLWithPath: destination.path + currentURL.path.dropFirst(entry.url.path.count))
                try await adoptRelocatedDocument(target)
            }
            expanded = Set(expanded.map { path in
                (path == entry.url.path || path.hasPrefix(entry.url.path + "/")) ? destination.path + path.dropFirst(entry.url.path.count) : path
            })
            expanded.insert(destination.deletingLastPathComponent().path)
            UserDefaults.standard.set(Array(expanded), forKey: "expanded:\(root.path)")
            workspaceNotice = failures.isEmpty ? "\(entry.name)을(를) 이동했습니다." : "이동은 완료했지만 일부 링크 보정에 실패했습니다. 원문은 복구 목록에 보관했습니다.\n" + failures.joined(separator: "\n")
            if !failures.isEmpty { errorMessage = workspaceNotice }
        } catch {
            if !didMove {
                for id in recoveryIDs { try? await store.removeRecovery(id) }
            } else if currentMoved, let currentURL {
                // Never keep autosave bound to the old path after the filesystem move succeeded.
                documentURL = URL(fileURLWithPath: destination.path + currentURL.path.dropFirst(entry.url.path.count))
                hasConflict = true; observeDocument()
            }
            showError(error)
        }
        if didMove, let scope = folderSearchScope, isInside(scope, entry.url) {
            folderSearchScope = URL(fileURLWithPath: destination.path + scope.path.dropFirst(entry.url.path.count))
        }
        refreshFolder(); invalidateFolderSearch()
    }

    private func adoptRelocatedDocument(_ url: URL) async throws {
        let disk = try await store.read(url)
        await finishRecoveryTask(); try await store.removeRecovery(recoveryID)
        persistPosition()
        let nextSession = UUID().uuidString
        bridge.send(message("relocate", ["text": disk.codec.originalText, "nextDocumentID": url.path,
            "nextSessionID": nextSession, "baseURL": url.deletingLastPathComponent().absoluteString]))
        documentURL = url; documentID = url.path; sessionID = nextSession; revision = 0
        text = disk.codec.originalText; codec = disk.codec; isDirty = false; hasConflict = false; desynchronized = false
        access.grant(url); observeDocument(); persistPosition()
        rememberDocument()
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    func trashWorkspaceItem(_ entry: FileEntry) {
        guard !workspaceBusy else { return }
        let alert = NSAlert()
        alert.messageText = "‘\(entry.name)’을(를) 휴지통으로 보낼까요?"
        alert.informativeText = entry.isDirectory ? "폴더 안의 모든 항목도 함께 이동합니다. 다른 문서의 연결은 자동 수정하지 않습니다." : "Finder의 휴지통에서 되돌릴 수 있습니다. 다른 문서의 연결은 자동 수정하지 않습니다."
        alert.addButton(withTitle: "휴지통으로 보내기"); alert.addButton(withTitle: "취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            guard let root = folderURL, await beginWorkspaceChange() else { return }
            defer { endWorkspaceChange() }
            guard await saveWorkspaceDocumentIfNeeded(in: entry.url) else { return }
            do {
                _ = try await workspaceFiles.trash(root: root, source: entry.url)
                if let documentURL, isInside(documentURL, entry.url) {
                    await finishRecoveryTask(); try await store.removeRecovery(recoveryID)
                    resetDocument(url: nil, codec: try DocumentCodec(data: Data()))
                }
                if let scope = folderSearchScope, isInside(scope, entry.url) { folderSearchScope = nil }
                expanded = expanded.filter { $0 != entry.url.path && !$0.hasPrefix(entry.url.path + "/") }
                refreshFolder(); invalidateFolderSearch(); workspaceNotice = "\(entry.name)을(를) 휴지통으로 보냈습니다."
            } catch { showError(error) }
        }
    }

    func showFolderSearch(scope: URL? = nil) {
        guard !workspaceBusy else { return }
        if folderSearchScope != scope { invalidateFolderSearch(); replacementReview = nil }
        folderSearchScope = scope; workspaceNotice = nil
        sidebarVisible = true; sidebarMode = "search"
        if folderURL == nil { chooseFolder() }
    }

    func invalidateFolderSearch() {
        folderSearchTask?.cancel(); searchGeneration = UUID(); folderSearchReport = nil; folderSearching = false
    }

    func runFolderSearch() {
        guard !workspaceBusy else { return }
        invalidateFolderSearch(); workspaceNotice = nil
        guard let root = folderSearchScope ?? folderURL, !folderQuery.isEmpty else { return }
        let generation = searchGeneration, options = FolderSearch.Options(query: folderQuery, caseSensitive: folderCaseSensitive)
        folderSearching = true
        folderSearchTask = Task {
            guard await beginWorkspaceChange() else { folderSearching = false; return }
            let ready = await saveWorkspaceDocumentIfNeeded(in: root)
            endWorkspaceChange()
            guard ready, !Task.isCancelled else { folderSearching = false; return }
            let result = await FolderSearch.scan(folder: root, options: options)
            guard generation == searchGeneration, !Task.isCancelled else { return }
            folderSearchReport = result; folderSearching = false
        }
    }

    func openSearchMatch(_ file: FolderSearch.FileResult, match: FolderSearch.Match) async {
        guard !workspaceBusy else { return }
        await open(file.url)
        guard documentURL == file.url else { return }
        do {
            try await syncSnapshot()
            guard !isDirty, DocumentCodec.hash(codec.originalData) == file.originalHash else {
                workspaceNotice = "검색 후 문서가 바뀌었습니다. 다시 검색해 주세요."; return
            }
            bridge.send(message("jump", ["from": match.range.lowerBound, "to": match.range.upperBound]))
        } catch { showError(error) }
    }

    func reviewFolderReplacement() {
        guard let root = folderSearchScope ?? folderURL, let report = folderSearchReport, report.isComplete, !report.files.isEmpty, !workspaceBusy else { return }
        replacementReview = FolderReplacementReview(root: root, query: folderQuery, replacement: folderReplacement, plan: report.replacementPlan)
    }

    func applyFolderReplacement(_ review: FolderReplacementReview, selected: Set<URL>) async -> FolderSearch.ApplyReport? {
        guard (folderSearchScope ?? folderURL) == review.root, !selected.isEmpty, await beginWorkspaceChange() else { return nil }
        defer { endWorkspaceChange() }
        guard await saveWorkspaceDocumentIfNeeded(in: review.root) else { return nil }
        let report = await FolderSearch.apply(plan: review.plan, replacement: review.replacement, including: selected, store: store)
        if let documentURL, report.outcomes.contains(where: { $0.url == documentURL && $0.status == .saved }) {
            do { try await adoptRelocatedDocument(documentURL) } catch { hasConflict = true; showError(error) }
        }
        invalidateFolderSearch(); refreshFolder()
        return report
    }

    func setQAWorkspace(_ root: URL) async throws {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--qa") || args.contains("--qa-session"), let index = args.firstIndex(of: "--qa-root"), args.indices.contains(index + 1),
              isInside(root, URL(fileURLWithPath: args[index + 1])) else { throw DocumentError.unsafePath }
        await setFolder(root)
    }
}
