import AppKit
import SwiftUI
import UniformTypeIdentifiers
#if SWIFT_PACKAGE
import MyMarkdownCore
#endif

struct OutlineEntry: Identifiable {
    var title: String; var level: Int; var from: Int
    var id: Int { from }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    let access = AccessManager()
    let bridge = EditorBridge()
    let store: FileStore
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
    @Published var rootEntries: [FileEntry] = []
    @Published var children: [String: [FileEntry]] = [:]
    @Published var expanded: Set<String> = []
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
    private var observation: FileObservation?
    private var folderObservation: FolderObservation?
    private var fileFolderObservation: FolderObservation?
    private var folderGeneration = UUID()
    private var startupDone = false

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
         "contentWidth": settings.contentWidth, "fontFamily": settings.fontFamily, "remoteImages": remoteImages]
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

    func editorReady() {
        sendDocument()
        guard !startupDone else { return }
        startupDone = true
        Task {
            do { recoveries = try await store.recoveries(); showRecovery = !recoveries.isEmpty } catch { showError(error) }
            if let path = UserDefaults.standard.string(forKey: "lastFolder"), let url = access.restore(path) { await setFolder(url) }
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "--open"), args.indices.contains(index + 1) { await open(URL(fileURLWithPath: args[index + 1])) }
            if args.contains("--qa") { await runAppQA() }
        }
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
                composing = body["composing"] as? Bool ?? false
                isDirty = text != codec.originalText; scheduleRecovery(); scheduleAutosave()
            } catch { desynchronized = true; showError(error) }
        case "metadata":
            guard body["revision"] as? Int == revision else { return }
            outline = (body["headings"] as? [[String: Any]] ?? []).compactMap {
                guard let title = $0["title"] as? String, let level = $0["level"] as? Int, let from = $0["from"] as? Int else { return nil }
                return OutlineEntry(title: title, level: level, from: from)
            }
            characters = body["characters"] as? Int ?? 0; words = body["words"] as? Int ?? 0; lines = body["lines"] as? Int ?? 1
        case "position":
            anchor = body["anchor"] as? Int ?? 0; head = body["head"] as? Int ?? anchor
            scrollTop = body["scrollTop"] as? Double ?? 0; visibleFrom = body["visibleFrom"] as? Int ?? 0
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

    func save(automatic: Bool = false) async -> Bool {
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
        guard !isSaving else { return false }
        do { try await syncSnapshot() } catch { showError(error); return false }
        guard !composing else { return false }
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
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
        guard !transitioning else { return }; transitioning = true; defer { transitioning = false }
        bridge.send(message("lock", ["locked": true])); defer { bridge.send(message("lock", ["locked": false])) }
        guard await prepareToLeave() else { return }
        resetDocument(url: nil, codec: try! DocumentCodec(data: Data()))
    }
    func chooseDocument() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { Task { await open(url) } }
    }
    func open(_ url: URL) async {
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
        autosaveTask?.cancel(); recoveryTask?.cancel()
        documentURL = url; documentID = url?.path ?? UUID().uuidString; sessionID = UUID().uuidString; recoveryID = UUID().uuidString
        self.codec = codec; text = codec.originalText; revision = 0; isDirty = false; hasConflict = false; desynchronized = false; composing = false
        errorMessage = nil; remoteImages = false; sourceMode = false; outline = []; anchor = 0; head = 0; scrollTop = 0
        access.retainAccess(for: [url, folderURL].compactMap { $0 })
        restorePosition(); sendDocument(); observeDocument()
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
        observation?.stop(); observation = nil; fileFolderObservation?.stop(); fileFolderObservation = nil
        guard let documentURL else { return }
        observation = FileObservation(url: documentURL) { [weak self] in Task { @MainActor in await self?.checkExternalChange() } }
        fileFolderObservation = FolderObservation(url: documentURL.deletingLastPathComponent()) { [weak self] in Task { await self?.checkExternalChange() } }
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
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.prompt = "폴더 열기"
        if panel.runModal() == .OK, let url = panel.url { Task { await setFolder(url) } }
    }
    func chooseAssetFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.directoryURL = documentURL?.deletingLastPathComponent()
        panel.message = "문서가 참조하는 이미지가 있는 폴더를 선택하세요."
        if panel.runModal() == .OK, let url = panel.url { access.grant(url); sendSettings() }
    }
    private func setFolder(_ url: URL) async {
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
        else if url.isFileURL, url.pathExtension.lowercased() == "md", access.canRead(url) { Task { await open(url) } }
    }

    private func persistPosition() {
        guard let documentURL else { return }
        UserDefaults.standard.set(["anchor": Double(anchor), "head": Double(head), "scrollTop": scrollTop], forKey: "position:\(documentURL.path)")
    }
    private func restorePosition() {
        guard let documentURL, let values = UserDefaults.standard.dictionary(forKey: "position:\(documentURL.path)") as? [String: Double] else { return }
        anchor = Int(values["anchor"] ?? 0); head = Int(values["head"] ?? Double(anchor)); scrollTop = values["scrollTop"] ?? 0
    }
    func restore(_ record: RecoveryRecord) async {
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
        guard args.contains("--qa"), let index = args.firstIndex(of: "--qa-root"), args.indices.contains(index + 1),
              url.standardizedFileURL.path.hasPrefix(URL(fileURLWithPath: args[index + 1]).standardizedFileURL.path + "/") else {
            throw DocumentError.unsafePath
        }
        access.grant(url)
        let disk = try await store.read(url)
        resetDocument(url: url, codec: disk.codec)
    }
}
