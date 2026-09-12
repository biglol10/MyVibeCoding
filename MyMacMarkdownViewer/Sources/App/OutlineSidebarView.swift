import SwiftUI
#if SWIFT_PACKAGE
import MyMarkdownCore
#endif

@MainActor
final class OutlineSidebarState: ObservableObject {
    @Published var query = "" { didSet { updateRows() } }
    @Published var collapsed: Set<Int> = [] { didSet { updateRows() } }
    private(set) var tree = OutlineNavigation([])
    @Published private(set) var rows: [OutlineNavigation.Row] = []
    func rebuild(_ entries: [OutlineEntry]) {
        guard tree.rows.map(\.entry) != entries else { return }
        tree = OutlineNavigation(entries); collapsed.removeAll()
    }
    func reset() {
        tree = OutlineNavigation([]); query = ""; collapsed.removeAll()
    }
    func updateRows() { rows = tree.visibleRows(query: query, collapsed: collapsed) }
}

struct OutlineSidebarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var navigation: OutlineSidebarState
    init(model: AppModel) {
        self.model = model; self.navigation = model.outlineNavigation
    }
    private var searching: Bool { !OutlineNavigation.normalized(navigation.query).isEmpty }

    var body: some View {
        let current = model.currentHeading
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("목차에서 찾기", text: $navigation.query).textFieldStyle(.plain)
                    .accessibilityLabel("목차에서 찾기")
                    .onSubmit { if let entry = navigation.tree.firstMatch(navigation.query) { model.jump(entry.from) } }
                    .onExitCommand { navigation.query = "" }
                if !navigation.query.isEmpty {
                    Button { navigation.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("목차 검색 지우기")
                }
            }.font(.system(size: 13)).padding(9)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 12).padding(.top, 4)
            HStack(spacing: 12) {
                Button("모두 접기") { navigation.collapsed = navigation.tree.collapsibleIDs }
                Button("모두 펼치기") { navigation.collapsed.removeAll() }
                Spacer(minLength: 0)
            }.font(.system(size: 11)).buttonStyle(.borderless)
                .disabled(searching || navigation.tree.collapsibleIDs.isEmpty)
                .padding(.horizontal, 14).padding(.vertical, 10)
            if navigation.rows.isEmpty {
                Text(searching ? "일치하는 제목이 없습니다." : "문서의 제목이 여기에 표시됩니다.")
                    .font(.callout).foregroundStyle(.secondary).padding(16)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(navigation.rows) { row in
                            HStack(alignment: .top, spacing: 0) {
                                if row.hasChildren {
                                    Button {
                                        if navigation.collapsed.contains(row.id) { navigation.collapsed.remove(row.id) }
                                        else { navigation.collapsed.insert(row.id) }
                                    } label: {
                                        Image(systemName: !searching && navigation.collapsed.contains(row.id) ? "chevron.right" : "chevron.down")
                                            .font(.system(size: 9, weight: .semibold)).frame(width: 24, height: 34)
                                    }.buttonStyle(.plain).disabled(searching)
                                        .accessibilityLabel("\(!searching && navigation.collapsed.contains(row.id) ? "펼치기" : "접기"): \(row.entry.title)")
                                        .accessibilityValue(!searching && navigation.collapsed.contains(row.id) ? "접힘" : "펼침")
                                } else { Color.clear.frame(width: 24, height: 34).accessibilityHidden(true) }
                                Button { model.jump(row.id) } label: {
                                    Text(row.entry.title.isEmpty ? "제목 없음" : row.entry.title)
                                        .font(.system(size: 13, weight: row.entry.level <= 2 ? .medium : .regular))
                                        .foregroundStyle(current == row.id ? .primary : .secondary)
                                        .lineLimit(3).lineSpacing(3).multilineTextAlignment(.leading)
                                        .padding(.vertical, 8).padding(.trailing, 8)
                                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                                }.buttonStyle(.plain).help(row.entry.title)
                                    .accessibilityAddTraits(current == row.id ? .isSelected : [])
                            }.padding(.leading, CGFloat(row.depth * 10))
                                .background(current == row.id ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 12)
                }
            }
        }
        .onAppear { navigation.rebuild(model.outline) }
        .onChange(of: model.outline) { _, entries in navigation.rebuild(entries) }
    }
}
