import SwiftUI
import AppKit
#if SWIFT_PACKAGE
import MyMarkdownCore
#endif

struct FolderSearchView: View {
    @ObservedObject var model: AppModel
    @State private var showsReplacement = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.folderURL == nil {
                    Text("폴더를 열어 여러 문서의 본문을 검색하세요.")
                        .foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    Button("폴더 열기…") { model.chooseFolder() }.controlSize(.large)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("본문 찾기").font(.headline)
                        TextField("찾을 글자", text: $model.folderQuery).textFieldStyle(.roundedBorder).controlSize(.large)
                            .onSubmit { model.runFolderSearch() }.accessibilityIdentifier("folder-query")
                        Toggle("대소문자 구분", isOn: $model.folderCaseSensitive)
                        Button { model.runFolderSearch() } label: {
                            Label("폴더에서 검색", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                        }.controlSize(.large).disabled(model.folderQuery.isEmpty || model.workspaceBusy)
                        Text("하위 폴더의 Markdown 본문을 검색합니다. 열린 문서의 변경은 먼저 저장합니다.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                    DisclosureGroup(isExpanded: $showsReplacement) {
                      VStack(alignment: .leading, spacing: 10) {
                        TextField("바꿀 글자", text: $model.folderReplacement).textFieldStyle(.roundedBorder).controlSize(.large)
                        Text("비워 두면 일치한 글자를 지웁니다.").font(.system(size: 12)).foregroundStyle(.secondary)
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        Button { model.reviewFolderReplacement() } label: {
                            Text("변경 내용 검토…").frame(maxWidth: .infinity)
                        }.controlSize(.large)
                            .disabled(model.folderSearchReport?.isComplete != true || model.folderSearchReport?.files.isEmpty != false || model.workspaceBusy)
                      }.padding(.top, 10)
                    } label: {
                        Text("찾은 글자 바꾸기").font(.headline)
                    }
                    Divider()
                    if model.folderSearching {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("검색 중…")
                            Spacer(minLength: 0)
                            Button("취소") { model.invalidateFolderSearch() }
                        }
                    }
                    if let notice = model.workspaceNotice {
                        Text(notice).foregroundStyle(.secondary).lineSpacing(4).textSelection(.enabled)
                    }
                    if let report = model.folderSearchReport {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("검색 결과").font(.headline)
                            Text("문서 \(report.files.count)개 · 일치 \(report.files.reduce(0) { $0 + $1.matches.count })곳")
                                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        if report.isTruncated {
                            Text("결과가 많아 일부만 표시합니다. 검색어를 좁혀 주세요. 전체 바꾸기는 잠겨 있습니다.")
                                .foregroundStyle(.orange).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(report.issues) { issue in
                            Text("\(model.relativePath(issue.url)): \(issue.message)")
                                .foregroundStyle(.orange).lineSpacing(4).textSelection(.enabled)
                        }
                        if report.files.isEmpty && report.isComplete {
                            Text("일치하는 본문이 없습니다.").foregroundStyle(.secondary)
                        }
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(report.files) { file in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(file.url.lastPathComponent).fontWeight(.semibold)
                                        .fixedSize(horizontal: false, vertical: true).help(file.url.path)
                                    let parent = model.relativePath(file.url.deletingLastPathComponent())
                                    if file.url.deletingLastPathComponent() != model.folderURL {
                                        Text(parent).font(.system(size: 12)).foregroundStyle(.secondary)
                                            .lineLimit(2).help(file.url.path)
                                    }
                                    ForEach(file.matches) { match in
                                        Button { Task { await model.openSearchMatch(file, match: match) } } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text("\(match.line)행 · \(match.column)열").font(.system(size: 12)).foregroundStyle(.secondary)
                                                Text(match.snippet).lineLimit(3).lineSpacing(4).multilineTextAlignment(.leading)
                                            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                                                .contentShape(Rectangle())
                                        }.buttonStyle(.plain).help(match.snippet).disabled(model.workspaceBusy)
                                    }
                                }
                            }
                        }
                    } else if !model.folderSearching {
                        Text("검색하면 문서별 결과가 여기에 표시됩니다.").foregroundStyle(.secondary)
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.font(.system(size: 13)).padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FolderReplaceView: View {
    @ObservedObject var model: AppModel
    let review: FolderReplacementReview
    @State private var selected: Set<URL> = []
    @State private var result: FolderSearch.ApplyReport?
    @State private var applying = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(result == nil ? "폴더 전체 바꾸기 검토" : "바꾸기 결과").font(.title2.bold())
            Text("‘\(review.query)’ → \(review.replacement.isEmpty ? "삭제" : "‘" + review.replacement + "’")").textSelection(.enabled)
            Text("선택한 파일만 저장합니다. 적용 직전 원본을 다시 확인하며, 파일별 저장 전 백업을 남깁니다. 여러 파일의 변경은 한 번의 실행 취소로 되돌릴 수 없습니다.")
                .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let result {
                        Text("\(result.savedCount)개 파일 저장 완료").font(.headline)
                        ForEach(result.outcomes) { outcome in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(label(outcome.status)).font(.headline)
                                Text(model.relativePath(outcome.url)).font(.system(size: 13)).lineSpacing(4)
                                if let message = outcome.message { Text(message).font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4) }
                            }.textSelection(.enabled)
                        }
                    } else {
                        ForEach(review.plan.files) { file in
                            VStack(alignment: .leading, spacing: 14) {
                                Toggle(isOn: Binding(get: { selected.contains(file.url) }, set: { if $0 { selected.insert(file.url) } else { selected.remove(file.url) } })) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(model.relativePath(file.url)).font(.headline).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                                        Text("일치 \(file.matches.count)곳").font(.system(size: 12)).foregroundStyle(.secondary)
                                    }
                                }
                                // Full before/after text is available; no truncation can hide a changed match.
                                DisclosureGroup("원문과 변경 후 전체 내용") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("변경 전").font(.caption.bold())
                                        Text(file.codec.originalText).font(.system(size: 13, design: .monospaced)).lineSpacing(4).textSelection(.enabled)
                                        Divider()
                                        Text("변경 후").font(.caption.bold())
                                        Text((try? FolderSearch.preview(file, replacement: review.replacement)) ?? "변경 내용을 만들 수 없습니다.")
                                            .font(.system(size: 13, design: .monospaced)).lineSpacing(4).textSelection(.enabled)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                                ForEach(file.matches) { match in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("\(match.line)행: \(match.snippet)").foregroundStyle(.secondary)
                                        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
                                            GridRow {
                                                Text("변경 전").foregroundStyle(.secondary)
                                                Text((file.codec.originalText as NSString).substring(with: NSRange(match.range)))
                                                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                                            }
                                            GridRow {
                                                Text("변경 후").foregroundStyle(.secondary)
                                                Text(review.replacement.isEmpty ? "(삭제)" : review.replacement).bold()
                                                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }.font(.system(size: 13, design: .monospaced)).lineSpacing(4).textSelection(.enabled).padding(.vertical, 6)
                                }
                            }.padding(16).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).id(result == nil ? "preview" : "result")
            }.frame(minHeight: 100, maxHeight: .infinity)
            Divider()
            HStack(spacing: 12) {
                if applying { ProgressView().controlSize(.small); Text("파일 저장 중…").font(.caption) }
                Spacer()
                Button(result == nil ? "취소" : "닫기") { model.replacementReview = nil }.keyboardShortcut(.cancelAction).disabled(applying)
                if result == nil {
                    Button("선택한 \(selected.count)개 파일에 적용") {
                        applying = true
                        Task { result = await model.applyFolderReplacement(review, selected: selected); applying = false }
                    }.disabled(selected.isEmpty || applying || model.workspaceBusy)
                }
            }
        }.controlSize(.large).padding(24).frame(width: 660, height: min(640, max(420, (NSScreen.main?.visibleFrame.height ?? 800) - 120)))
            .onAppear { selected = Set(review.plan.files.map(\.url)) }
            .interactiveDismissDisabled(applying)
    }
    private func label(_ status: FolderSearch.ApplyOutcome.Status) -> String {
        switch status {
        case .saved: "저장됨"
        case .excluded: "선택 제외"
        case .stale: "외부 변경으로 중단"
        case .failed: "저장 실패"
        case .notAttempted: "적용 안 됨"
        }
    }
}
