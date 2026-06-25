import SwiftData
import SwiftUI
import MyMacCalendarCore

struct QuickAddView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var parsed: QuickAddResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Add")
                .font(.title3.weight(.semibold))

            TextField("6/30 codex 만료", text: $input)
                .textFieldStyle(.roundedBorder)
                .onChange(of: input) { _, newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    parsed = trimmed.isEmpty ? nil : QuickAddParser().parse(newValue)
                }
                .onSubmit(parse)

            if let parsed {
                GroupBox("Preview") {
                    VStack(alignment: .leading) {
                        Text(parsed.title)
                            .font(.headline)
                        Text(parsed.startDate.formatted(date: .complete, time: .omitted))
                            .foregroundStyle(.secondary)
                        if parsed.needsConfirmation {
                            Text("Date needs confirmation.")
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsed == nil)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func parse() {
        parsed = QuickAddParser().parse(input)
    }

    private func save() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        let result = parsed ?? QuickAddParser().parse(trimmed)
        modelContext.insert(CalendarEvent(title: result.title, startDate: result.startDate, endDate: result.endDate))
        try? modelContext.save()
        dismiss()
    }
}
