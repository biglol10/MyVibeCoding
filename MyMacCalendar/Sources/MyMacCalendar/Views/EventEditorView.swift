import SwiftData
import SwiftUI
import MyMacCalendarCore

struct EventEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let event: CalendarEvent?
    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var notes: String
    @State private var recurrence: EventRecurrence
    @State private var notificationOffsets: Set<Int>
    @State private var showingDeleteConfirmation = false

    init(event: CalendarEvent? = nil, defaultDate: Date = Date()) {
        self.event = event
        _title = State(initialValue: event?.title ?? "")
        _startDate = State(initialValue: event?.startDate ?? defaultDate)
        _endDate = State(initialValue: event?.endDate ?? defaultDate)
        _notes = State(initialValue: event?.notes ?? "")
        _recurrence = State(initialValue: event?.recurrence ?? .none)
        _notificationOffsets = State(initialValue: Set(event?.notificationOffsetsDays ?? [1]))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(event == nil ? "New Event" : "Edit Event")
                .font(.title3.weight(.semibold))

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            DatePicker("Start", selection: $startDate, displayedComponents: .date)
            DatePicker("End", selection: $endDate, displayedComponents: .date)

            Picker("Repeat", selection: $recurrence) {
                Text("None").tag(EventRecurrence.none)
                Text("Weekly").tag(EventRecurrence.weekly)
                Text("Monthly").tag(EventRecurrence.monthly)
                Text("Yearly").tag(EventRecurrence.yearly)
            }

            VStack(alignment: .leading) {
                Text("Notifications")
                    .font(.subheadline.weight(.semibold))
                ForEach([7, 2, 1, 0], id: \.self) { offset in
                    Toggle(label(for: offset), isOn: Binding(
                        get: { notificationOffsets.contains(offset) },
                        set: { isOn in
                            if isOn {
                                notificationOffsets.insert(offset)
                            } else {
                                notificationOffsets.remove(offset)
                            }
                        }
                    ))
                }
            }

            TextEditor(text: $notes)
                .frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))

            HStack {
                if event != nil {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .confirmationDialog("Delete this event?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(recurrence == .none ? "This event will be removed." : "The entire repeating series will be removed.")
        }
    }

    private func label(for offset: Int) -> String {
        offset == 0 ? "On the day" : "\(offset) days before"
    }

    private func save() {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedStart = Calendar.current.startOfDay(for: startDate)
        let normalizedEnd = Calendar.current.startOfDay(for: max(endDate, startDate))

        if let event {
            event.title = normalizedTitle
            event.startDate = normalizedStart
            event.endDate = normalizedEnd
            event.notes = notes
            event.recurrence = recurrence
            event.notificationOffsetsDays = notificationOffsets.sorted(by: >)
            event.updatedAt = Date()
        } else {
            modelContext.insert(
                CalendarEvent(
                    title: normalizedTitle,
                    startDate: normalizedStart,
                    endDate: normalizedEnd,
                    notes: notes,
                    recurrence: recurrence,
                    notificationOffsetsDays: notificationOffsets.sorted(by: >)
                )
            )
        }

        try? modelContext.save()
        dismiss()
    }

    private func delete() {
        if let event {
            modelContext.delete(event)
            try? modelContext.save()
        }
        dismiss()
    }
}
