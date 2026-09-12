import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MyMarkdownCore
#endif

@main
struct MyMarkdownViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    var body: some Scene {
        Window("MyMarkdownViewer", id: "main") {
            WorkspaceView(model: model)
                .frame(minWidth: 760, minHeight: 500)
                .background(Color(nsColor: model.canvasNSColor))
                .background(WindowAccessor())
                .onOpenURL { url in Task { await model.open(url) } }
        }
        .defaultSize(width: 1120, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("새 문서") { Task { await model.newDocument() } }.keyboardShortcut("n")
                Button("열기…") { model.chooseDocument() }.keyboardShortcut("o")
                Button("폴더 열기…") { model.chooseFolder() }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .saveItem) {
                Button("저장") { Task { _ = await model.save() } }.keyboardShortcut("s")
                Button("다른 이름으로 저장…") { Task { _ = await model.saveAs() } }.keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("HTML로 내보내기…") { Task { await model.exportHTML() } }
                Button("PDF로 내보내기…") { Task { await model.exportPDF() } }
                Button("프린트…") { Task { await model.printDocument() } }.keyboardShortcut("p", modifiers: [.command, .option])
                Divider()
                Button("Finder에서 보기") { model.reveal() }
                Button("복구할 문서 보기…") { model.openRecoveryList() }
                Divider()
                Button("닫기") { NSApp.keyWindow?.performClose(nil) }.keyboardShortcut("w")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("실행 취소") { model.command("undo") }.keyboardShortcut("z")
                Button("다시 실행") { model.command("redo") }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Divider()
                Button("문서에서 찾기") { model.command("find") }.keyboardShortcut("f")
                Button("폴더 전체 검색") { model.showFolderSearch() }.keyboardShortcut("f", modifiers: [.command, .shift])
                Button("찾아 바꾸기") { model.command("replace") }.keyboardShortcut("f", modifiers: [.command, .option])
            }
            CommandMenu("서식") {
                Button("굵게") { model.command("bold") }.keyboardShortcut("b")
                Button("기울임") { model.command("italic") }.keyboardShortcut("i")
                Button("링크") { model.command("link") }.keyboardShortcut("k")
                Button("인라인 코드") { model.command("code") }
                Divider()
                Button("제목") { model.command("heading") }
                Button("인용") { model.command("quote") }
                Button("목록") { model.command("list") }
                Button("체크리스트") { model.command("task") }
                Button("코드 블록") { model.command("codeBlock") }
                Divider()
                Menu("삽입") {
                    Button("표 삽입") { model.command("table") }
                    Button("목차") { model.command("toc") }
                    Button("각주") { model.command("footnote") }
                    Button("문서 속성") { model.command("frontMatter") }
                    Button("번호 목록") { model.command("orderedList") }
                    Button("취소선") { model.command("strike") }
                    Button("가로선") { model.command("horizontalRule") }
                    Button("수식 블록") { model.command("mathBlock") }
                }
                Button("이미지 삽입…") { model.chooseImage() }
            }
            CommandGroup(after: .sidebar) {
                Button("빠른 파일 열기…") { model.quickQuery = ""; model.quickOpen = true }.keyboardShortcut("p")
                Button(model.sourceMode ? "라이브 편집" : "원문 모드") { model.command("source") }.keyboardShortcut("m", modifiers: [.command, .shift])
                Divider()
                Toggle("집중 모드", isOn: $model.settings.focusMode)
                Toggle("타자기 모드", isOn: $model.settings.typewriterMode)
            }
        }
        Settings { SettingsView(model: model) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var closeAuthorized = false
    private var closing = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
        AppModel.shared.applyAppearance()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(themeChanged), name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
    }
    @objc private func themeChanged() { AppModel.shared.systemAppearanceChanged() }
    func applicationDidBecomeActive(_ notification: Notification) { AppModel.shared.didBecomeActive() }
    func applicationWillResignActive(_ notification: Notification) { AppModel.shared.persistReadingPosition() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if closeAuthorized { return .terminateNow }
        Task { let allowed = await AppModel.shared.canClose(); sender.reply(toApplicationShouldTerminate: allowed) }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closeAuthorized { return true }
        guard !closing else { return false }; closing = true
        Task {
            if await AppModel.shared.canClose() { closeAuthorized = true; sender.close() }
            closing = false
        }
        return false
    }
    func application(_ application: NSApplication, open urls: [URL]) { if let url = urls.first { Task { await AppModel.shared.open(url) } } }
}

struct WindowAccessor: NSViewRepresentable {
    @ObservedObject private var model = AppModel.shared
    func makeNSView(context: Context) -> NSView { AccessorView() }
    func updateNSView(_ nsView: NSView, context: Context) { nsView.window?.backgroundColor = model.canvasNSColor }
    final class AccessorView: NSView {
        private let closeDelegate = CloseDelegate()
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                window.backgroundColor = AppModel.shared.canvasNSColor
                window.delegate = closeDelegate
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
            }
        }
    }
    @MainActor final class CloseDelegate: NSObject, NSWindowDelegate {
        private var authorized = false
        private var pending = false
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if authorized { return true }
            guard !pending else { return false }; pending = true
            Task {
                if await AppModel.shared.canClose() { authorized = true; sender.close() }
                pending = false
            }
            return false
        }
    }
}
