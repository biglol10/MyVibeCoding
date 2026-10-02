import SwiftUI

struct AdvancedSearchControls: View {
    @EnvironmentObject private var store: ExplorerStore
    @State private var minimum = ""
    @State private var maximum = ""
    @State private var validation: String?
    private var options: AdvancedSearchOptions { store.searchOptions.advanced ?? AdvancedSearchOptions() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L10n.text("Text contains"), text: Binding(
                get: { options.content },
                set: { value in update { $0.content = value } }
            ))
            .textFieldStyle(.roundedBorder)
            .disabled(store.activePane.location.isArchive)
            if store.activePane.location.isArchive {
                Text(L10n.text("Content search is available after extracting the ZIP.")).font(.caption).foregroundStyle(.secondary)
            }
            Text(L10n.text("UTF-8 / UTF-16 text files up to 10 MiB. Links, binary files and document formats are excluded."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField(L10n.text("Minimum bytes"), text: $minimum)
                TextField(L10n.text("Maximum bytes"), text: $maximum)
            }.textFieldStyle(.roundedBorder)
            .onChange(of: minimum) { _, _ in applySizes() }
            .onChange(of: maximum) { _, _ in applySizes() }
            if let validation { Text(validation).font(.caption).foregroundStyle(.red) }
            Toggle(L10n.text("Modified from"), isOn: Binding(
                get: { options.modifiedFrom != nil },
                set: { enabled in update { $0.modifiedFrom = enabled ? Calendar.current.startOfDay(for: Date()) : nil } }
            ))
            if options.modifiedFrom != nil {
                DatePicker(L10n.text("From"), selection: Binding(
                    get: { options.modifiedFrom ?? Date() },
                    set: { value in update { $0.modifiedFrom = Calendar.current.startOfDay(for: value) } }
                ), displayedComponents: .date)
            }
            Toggle(L10n.text("Modified through"), isOn: Binding(
                get: { options.modifiedBefore != nil },
                set: { enabled in update { $0.modifiedBefore = enabled ? endOfDay(Date()) : nil } }
            ))
            if options.modifiedBefore != nil {
                DatePicker(L10n.text("Through"), selection: Binding(
                    get: { (options.modifiedBefore ?? Date()).addingTimeInterval(-1) },
                    set: { value in update { $0.modifiedBefore = endOfDay(value) } }
                ), displayedComponents: .date)
            }
        }
        .onAppear { syncSizes() }
        .onChange(of: store.searchOptions.advanced) { _, _ in
            // Keep transient invalid input visible; synchronize when filters are cleared externally.
            if store.searchOptions.advanced == nil { syncSizes() }
        }
    }
    private func update(_ mutation: (inout AdvancedSearchOptions) -> Void) {
        var value = options
        mutation(&value)
        store.setAdvancedSearch(value)
    }
    private func endOfDay(_ date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date)) ?? date
    }
    private func syncSizes() {
        minimum = options.minimumBytes.map(String.init) ?? ""
        maximum = options.maximumBytes.map(String.init) ?? ""
        validation = nil
    }
    private func applySizes() {
        let low = Int64(minimum), high = Int64(maximum)
        guard (minimum.isEmpty || (low != nil && low! >= 0)),
              (maximum.isEmpty || (high != nil && high! >= 0)),
              low == nil || high == nil || low! <= high! else {
            validation = "Enter nonnegative byte counts; minimum must not exceed maximum."
            return
        }
        validation = nil
        update { $0.minimumBytes = low; $0.maximumBytes = high }
    }
}
