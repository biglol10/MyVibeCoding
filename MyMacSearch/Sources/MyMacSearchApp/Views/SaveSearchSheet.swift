import MyMacSearchCore
import SwiftUI

struct SaveSearchSheet: View {
    let query: String
    let sort: SearchSort
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save Search")
                .font(.headline)
            TextField("Name", text: $name)
            LabeledContent("Query") {
                Text(query).lineLimit(2)
            }
            LabeledContent("Sort") {
                Text(sort.displayName)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

extension SearchSort {
    var displayName: String {
        switch self {
        case .relevance: "Relevance"
        case .nameAscending: "Name (A–Z)"
        case .nameDescending: "Name (Z–A)"
        case .pathAscending: "Path (A–Z)"
        case .pathDescending: "Path (Z–A)"
        case .modifiedNewest: "Modified (Newest)"
        case .modifiedOldest: "Modified (Oldest)"
        case .sizeLargest: "Size (Largest)"
        case .sizeSmallest: "Size (Smallest)"
        case .kindThenName: "Kind, then Name"
        }
    }
}
