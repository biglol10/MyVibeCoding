import SwiftUI

public struct BatchRenameRequest: Identifiable {
    public let id = UUID()
    public let paneID: PaneID
    public let entries: [FileEntry]
}

struct BatchRenameView: View {
    @EnvironmentObject private var store: ExplorerStore
    @Environment(\.dismiss) private var dismiss
    let request: BatchRenameRequest
    @State private var rule = BatchRenameRule()
    @State private var plans: [BatchRenamePlan] = []
    @State private var error: String?
    @State private var applying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("Batch Rename")).font(.title2)
            Text(L10n.text("Preview every change. Extensions are preserved; existing files are never replaced.")).font(.callout).foregroundStyle(.secondary)
            HStack { TextField(L10n.text("Find in name"), text: $rule.find); TextField(L10n.text("Replace with"), text: $rule.replacement) }
            HStack { TextField(L10n.text("Prefix"), text: $rule.prefix); TextField(L10n.text("Suffix"), text: $rule.suffix) }
            HStack { Toggle(L10n.text("Append numbering"), isOn: $rule.numbered); if rule.numbered { TextField(L10n.text("Start"), value: $rule.start, format: .number).frame(width: 80) } }
            List {
                ForEach(Array(request.entries.enumerated()), id: \.element.id) { index, entry in
                    HStack {
                        Text(entry.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(rule.name(for: entry, index: index)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(height: 260)
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Text("\(plans.count) changes").foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(applying)
                Button(L10n.text("Rename")) {
                    applying = true
                    let captured = plans
                    Task { await store.applyBatchRename(captured, inPane: request.paneID); dismiss() }
                }.keyboardShortcut(.defaultAction).disabled(error != nil || plans.isEmpty || applying)
            }
        }.padding(20).frame(width: 660).textFieldStyle(.roundedBorder)
        .disabled(applying)
        .onAppear { preview() }
        .onChange(of: rule) { _, _ in preview() }
    }
    private func preview() {
        do { plans = try BatchRenameService.plan(entries: request.entries, rule: rule); error = nil }
        catch { plans = []; self.error = error.localizedDescription }
    }
}
