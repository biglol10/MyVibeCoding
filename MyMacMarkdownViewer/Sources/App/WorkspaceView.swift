import SwiftUI
import AppKit
#if SWIFT_PACKAGE
import MyMarkdownCore
#endif

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @AppStorage("sidebarWidth") private var sidebarWidth = 234.0
    @State private var dragStartWidth: CGFloat?
    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if model.sidebarVisible {
                    sidebar.frame(width: resolvedSidebarWidth(in: geometry.size.width)).clipped()
                    sidebarDivider(in: geometry.size.width)
                }
                VStack(spacing: 0) {
                    if let error = model.errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                                Text(error).font(.callout).textSelection(.enabled)
                                Spacer()
                                Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("알림 닫기")
                            }
                            if model.hasConflict {
                                HStack {
                                    Button("디스크 버전 열기") { Task { await model.reloadFromDisk() } }
                                    Button("편집본 별도 저장") { Task { _ = await model.saveAs() } }
                                    Button("나중에 결정") { model.errorMessage = nil }
                                }.controlSize(.small)
                            }
                        }.padding(12).background(.quaternary)
                        Divider()
                    }
                    EditorWebView(model: model)
                        .overlay { if model.isLoading { ProgressView("문서 불러오는 중…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
                }.frame(minWidth: 0, maxWidth: .infinity)
            }
            Divider()
            HStack(spacing: 14) {
                Circle().fill(model.hasConflict ? Color.orange : (model.isDirty ? Color.secondary : Color.secondary.opacity(0.35))).frame(width: 5, height: 5)
                Text(model.status)
                Spacer()
                Text("\(model.characters.formatted())자")
                Text("\(model.words.formatted())단어")
                Text(model.sourceMode ? "원문" : "라이브 편집")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 16).frame(height: 28).background { chromeBackground }
        }
        .coordinateSpace(name: "workspace")
        .navigationTitle(model.title)
        .toolbar(removing: systemTitleItem)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }.help("사이드바 표시 / 숨기기")
            }
            ToolbarItem(placement: .principal) {
                Text(model.title).font(.headline).lineLimit(1).truncationMode(.middle)
                    .frame(width: min(340, max(120, geometry.size.width - 420)))
                    .help(model.documentURL?.path ?? model.title)
                    .accessibilityIdentifier("document-title")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.quickQuery = ""; model.quickOpen = true } label: { Image(systemName: "magnifyingglass") }.help("빠른 파일 열기 · ⌘P")
                Button { model.command("source") } label: { Image(systemName: model.sourceMode ? "doc.richtext" : "chevron.left.forwardslash.chevron.right") }.help("라이브 편집 / 원문 · ⌘⇧M")
                Menu {
                    Button("문서 열기…") { model.chooseDocument() }
                    Button("폴더 열기…") { model.chooseFolder() }
                    Button("이미지 삽입…") { model.chooseImage() }
                    Divider()
                    Toggle("집중 모드", isOn: $model.settings.focusMode)
                    Toggle("타자기 모드", isOn: $model.settings.typewriterMode)
                    Toggle("외부 이미지 불러오기", isOn: Binding(get: { model.remoteImages }, set: { _ in model.toggleRemoteImages() }))
                    SettingsLink { Text("읽기 설정…") }
                } label: { Image(systemName: "ellipsis.circle") }.help("문서 옵션")
            }
        }
        .sheet(isPresented: $model.quickOpen) { QuickOpenView(model: model) }
        .sheet(isPresented: $model.showRecovery) { RecoveryView(model: model) }
        .sheet(item: $model.replacementReview) { review in FolderReplaceView(model: model, review: review) }
        }
    }

    private func resolvedSidebarWidth(in windowWidth: CGFloat) -> CGFloat {
        clampedSidebarWidth(sidebarWidth, in: windowWidth)
    }

    private var systemTitleItem: ToolbarDefaultItemKind? {
        if #available(macOS 15, *) { return .title }
        return nil
    }

    @ViewBuilder private var chromeBackground: some View {
        if model.settings.theme == .night { Color(nsColor: model.nightChromeNSColor) }
        else { Rectangle().fill(.bar) }
    }

    private func clampedSidebarWidth(_ proposed: CGFloat, in windowWidth: CGFloat) -> CGFloat {
        min(max(200, proposed.isFinite ? proposed : 234), max(200, min(560, windowWidth - 407)))
    }

    private func sidebarDivider(in windowWidth: CGFloat) -> some View {
        Rectangle().fill(Color.clear).frame(width: 7)
            .overlay { Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1) }
            .contentShape(Rectangle())
            .onHover { NSCursor.resizeLeftRight.set(); if !$0 { NSCursor.arrow.set() } }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("workspace"))
                .onChanged { value in
                    let start = dragStartWidth ?? resolvedSidebarWidth(in: windowWidth)
                    dragStartWidth = start
                    sidebarWidth = clampedSidebarWidth(start + value.translation.width, in: windowWidth)
                }
                .onEnded { _ in dragStartWidth = nil })
            .accessibilityLabel("사이드바 너비")
            .accessibilityValue("\(Int(resolvedSidebarWidth(in: windowWidth)))")
            .accessibilityAdjustableAction { direction in
                let change: CGFloat = direction == .increment ? 20 : -20
                sidebarWidth = clampedSidebarWidth(resolvedSidebarWidth(in: windowWidth) + change, in: windowWidth)
            }
            .help("드래그하여 사이드바 너비 조절")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("사이드바", selection: $model.sidebarMode) {
                Text("파일").tag("files"); Text("목차").tag("outline"); Text("검색").tag("search")
            }.pickerStyle(.segmented).labelsHidden().padding(12)
            if model.sidebarMode == "files" {
                HStack(spacing: 4) {
                    Text(model.folderURL?.lastPathComponent ?? "작업 폴더").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).lineLimit(2).lineSpacing(3).truncationMode(.middle)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).help(model.folderURL?.path ?? "작업 폴더")
                    if model.folderURL != nil {
                        Menu {
                            Button("새 문서…") { model.createWorkspaceItem(in: nil, folder: false) }
                            Button("새 폴더…") { model.createWorkspaceItem(in: nil, folder: true) }
                        } label: { Image(systemName: "plus").frame(width: 26, height: 28) }.menuStyle(.borderlessButton).fixedSize()
                            .help("작업 폴더에 만들기").disabled(model.workspaceBusy)
                    }
                    Button { model.chooseFolder() } label: { Image(systemName: "folder.badge.plus").frame(width: 28, height: 28) }.buttonStyle(.plain).help("폴더 열기")
                    Button { Task { await model.revealCurrentFileInSidebar() } } label: {
                        Image(systemName: "scope").frame(width: 28, height: 28)
                    }.buttonStyle(.plain)
                        .help(model.currentFileRevealUnavailableReason ?? "현재 문서 찾기 · 파일 목록에서 보기")
                        .accessibilityLabel("현재 문서 찾기")
                        .accessibilityIdentifier("reveal-current-document")
                        .disabled(model.currentFileRevealUnavailableReason != nil)
                }.padding(.horizontal, 14).padding(.vertical, 8)
                if model.folderURL == nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("문서가 있는 폴더를 열면\n파일을 빠르게 찾아 읽을 수 있습니다.").font(.callout).foregroundStyle(.secondary).lineSpacing(4)
                        Button("폴더 열기…") { model.chooseFolder() }
                        Button("문서 열기…") { model.chooseDocument() }.buttonStyle(.link)
                    }.padding(16)
                } else {
                    GeometryReader { size in
                        ScrollViewReader { proxy in
                            ScrollView {
                                FileTreeRows(model: model, rows: model.visibleFileRows, width: max(0, size.size.width - 12))
                                    .padding(.horizontal, 6).padding(.bottom, 16)
                            }
                            .task(id: model.fileRevealRequest?.id) {
                                guard let request = model.fileRevealRequest else { return }
                                defer { model.completeSidebarReveal(request.id) }
                                // Let the newly expanded flat rows enter the view
                                // before asking the sidebar's own scroller to move.
                                await Task.yield()
                                guard !Task.isCancelled, model.sessionID == request.sessionID,
                                      model.visibleFileRows.contains(where: { $0.id == request.path }) else { return }
                                proxy.scrollTo(request.path, anchor: .center)
                            }
                        }
                    }
                }
            } else if model.sidebarMode == "search" {
                FolderSearchView(model: model)
            } else {
                OutlineSidebarView(model: model).id(model.sessionID)
            }
            Spacer(minLength: 0)
            HStack {
                if model.indexing { ProgressView().controlSize(.mini); Text("파일 찾는 중…") }
                else { Text(model.folderURL == nil ? "파일은 원래 위치에 보관됩니다" : "\(model.indexedFiles.count)개의 Markdown 문서") }
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(14)
        }.frame(maxHeight: .infinity).background { chromeBackground }
    }
}

private struct FileTreeRows: View {
    @ObservedObject var model: AppModel
    let rows: [FileTreeRow]
    let width: CGFloat
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(rows) { row in
                let entry = row.entry
                Button {
                    if entry.isDirectory { model.toggleFolder(entry) }
                    else { Task { await model.open(entry.url) } }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: entry.isDirectory ? (model.expanded.contains(entry.id) ? "chevron.down" : "chevron.right") : "doc.text")
                            .font(.system(size: entry.isDirectory ? 9 : 12)).foregroundStyle(.secondary).frame(width: 14)
                        if entry.isDirectory { Image(systemName: "folder").foregroundStyle(.secondary).frame(width: 16) }
                        Text(entry.name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    }.padding(.leading, min(CGFloat(row.depth) * 13 + 8, max(8, width - 110))).padding(.trailing, 8).frame(width: width, height: 32)
                        .contentShape(Rectangle())
                        .background(model.isCurrentSidebarFile(entry) ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain).help(entry.url.path).accessibilityLabel(entry.name)
                    .id(row.id)
                    .accessibilityAddTraits(model.isCurrentSidebarFile(entry) ? .isSelected : [])
                    .contextMenu {
                        Button(entry.isDirectory ? "펼치기" : "열기") { model.openWorkspaceItem(entry) }
                        Divider()
                        Button("새 문서…") { model.createWorkspaceItem(in: entry.isDirectory ? entry.url : entry.url.deletingLastPathComponent(), folder: false) }
                        Button("새 폴더…") { model.createWorkspaceItem(in: entry.isDirectory ? entry.url : entry.url.deletingLastPathComponent(), folder: true) }
                        Button("이 폴더에서 검색") { model.searchWorkspaceItem(entry) }
                        Divider()
                        Button("복제") { model.duplicateWorkspaceItem(entry) }
                        Button("이름 변경…") { model.renameWorkspaceItem(entry) }
                        Button("이동…") { model.chooseWorkspaceDestination(entry) }
                        Button("휴지통으로 보내기…", role: .destructive) { model.trashWorkspaceItem(entry) }
                        Divider()
                        Button("경로 복사") { model.copyWorkspacePath(entry) }
                        Button("Finder에서 보기") { model.reveal(entry.url) }
                        Button("정보 보기") { model.showWorkspaceInfo(entry) }
                    }.disabled(model.workspaceBusy)
            }
        }.frame(width: width).clipped()
    }
}

private struct QuickOpenView: View {
    @ObservedObject var model: AppModel
    @State private var selection: URL?
    @FocusState private var focused: Bool
    var body: some View {
        let candidates = model.filteredFiles
        let selectedFile = selection.flatMap { candidates.contains($0) ? $0 : nil } ?? candidates.first
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("파일 이름이나 경로로 찾기", text: $model.quickQuery).textFieldStyle(.plain).focused($focused)
                    .onSubmit { open(selectedFile) }
                if model.folderURL != nil {
                    Button { model.refreshFolder() } label: { Image(systemName: "arrow.clockwise") }
                        .help("파일 목록 새로 고침").accessibilityLabel("파일 목록 새로 고침")
                        .disabled(model.indexing)
                }
                Button("닫기") { model.quickOpen = false }.keyboardShortcut(.cancelAction)
            }.padding(18)
            Divider()
            if model.folderURL == nil {
                ContentUnavailableView { Label("폴더를 먼저 열어 주세요", systemImage: "folder") } actions: {
                    Button("폴더 열기…") { model.quickOpen = false; model.chooseFolder() }
                }.frame(height: 300)
            } else {
                List(candidates, id: \.self, selection: $selection) { url in
                    HStack { Image(systemName: "doc.text").foregroundStyle(.secondary); VStack(alignment: .leading, spacing: 3) {
                        Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Text(model.relativePath(url)).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                    } }.padding(.vertical, 3).tag(url).onTapGesture(count: 2) { open(url) }
                }.frame(height: 320)
                    .overlay {
                        if candidates.isEmpty {
                            Text(model.indexing ? "파일 목록 갱신 중…" : "일치하는 파일이 없습니다.")
                                .foregroundStyle(.secondary).allowsHitTesting(false)
                        }
                    }
                HStack {
                    Text(model.indexing ? "파일 목록 갱신 중…" : "이름과 상대 경로에서 검색합니다").foregroundStyle(.secondary)
                    Spacer()
                    Button("열기") { open(selectedFile) }.keyboardShortcut(.defaultAction).disabled(selectedFile == nil)
                }.font(.caption).padding(12)
            }
        }.frame(width: 560).onAppear {
            focused = true; selection = candidates.first
            if model.folderURL != nil { model.refreshFolder() }
        }
            .onChange(of: model.quickQuery) { _, _ in selection = candidates.first }
            .onChange(of: candidates) { _, files in
                if let selection, files.contains(selection) { return }
                selection = files.first
            }
    }
    private func open(_ url: URL?) { guard let url, model.filteredFiles.contains(url) else { return }; model.quickOpen = false; Task { await model.open(url) } }
}

private struct RecoveryView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("복구할 문서").font(.title2.bold())
            Text("저장이 끝나지 않은 편집본입니다. 원본을 덮어쓰지 않고 내용을 확인할 수 있습니다.").foregroundStyle(.secondary)
            List(model.recoveries) { record in
                HStack { VStack(alignment: .leading) {
                    Text(record.path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "새 문서")
                    Text(record.date.formatted()).font(.caption).foregroundStyle(.secondary)
                }; Spacer(); Button("복구") { Task { await model.restore(record) } } }
            }.frame(height: 240)
            HStack { Spacer(); Button("나중에") { model.showRecovery = false }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 570)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section("화면") {
                Picker("테마", selection: $model.settings.theme) { ForEach(ThemeChoice.allCases, id: \.self) { Text($0.label).tag($0) } }
                Picker("본문 글꼴", selection: $model.settings.fontFamily) { Text("시스템 고딕").tag("system"); Text("명조").tag("serif"); Text("고정폭").tag("mono") }
                HStack { Text("글자 크기"); Slider(value: $model.settings.fontSize, in: 12...30, step: 1); Text("\(Int(model.settings.fontSize))px").monospacedDigit().frame(width: 44) }
                HStack { Text("줄 간격"); Slider(value: $model.settings.lineHeight, in: 1.3...2.4, step: 0.1); Text(model.settings.lineHeight.formatted(.number.precision(.fractionLength(1)))).monospacedDigit().frame(width: 44) }
                HStack { Text("읽기 폭"); Slider(value: $model.settings.contentWidth, in: 500...1200, step: 20); Text("\(Int(model.settings.contentWidth))").monospacedDigit().frame(width: 44) }
            }
            Section("저장") { Toggle("입력 후 자동 저장", isOn: $model.settings.autosave); Text("입력을 멈춘 뒤 1초 후 저장합니다. 외부 변경이 발견되면 자동 저장을 멈춥니다.").font(.caption).foregroundStyle(.secondary) }
            Section("편집") {
                Toggle("집중 모드", isOn: $model.settings.focusMode)
                Text("현재 문단을 또렷하게 표시합니다.").font(.caption).foregroundStyle(.secondary)
                Toggle("타자기 모드", isOn: $model.settings.typewriterMode)
                Text("입력 중인 줄을 화면 가운데에 가깝게 유지합니다.").font(.caption).foregroundStyle(.secondary)
            }
            Section { Button("읽기 설정 초기화") { let autosave = model.settings.autosave; model.settings = ReadingSettings(); model.settings.autosave = autosave } }
        }.formStyle(.grouped).padding(10).frame(width: 490, height: 500)
    }
}
