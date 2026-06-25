import SwiftUI
import MyMacCalendarCore

struct AgendaPanelView: View {
    let selectedDate: Date
    let events: [CalendarEvent]
    let onSelectEvent: (CalendarEvent) -> Void
    let onSelectOccurrence: (EventOccurrence) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(selectedDate.formatted(.dateTime.year().month().day().weekday()))
                .font(.headline)

            GroupBox("Selected Day") {
                list(eventsForSelectedDate)
            }

            GroupBox("Upcoming") {
                occurrenceList(upcomingOccurrences)
            }

            Spacer()
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var eventsForSelectedDate: [CalendarEvent] {
        events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: selectedDate) }
    }

    private var upcomingOccurrences: [EventOccurrence] {
        EventService().upcomingOccurrences(from: selectedDate, events: events, limit: 8)
    }

    private func list(_ items: [CalendarEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if items.isEmpty {
                Text("No events")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.id) { event in
                    Button {
                        onSelectEvent(event)
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading) {
                                Text(event.title)
                                    .font(.body.weight(.medium))
                                Text(event.startDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func occurrenceList(_ items: [EventOccurrence]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if items.isEmpty {
                Text("No events")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.startDate) { occurrence in
                    Button {
                        onSelectOccurrence(occurrence)
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading) {
                                Text(occurrence.title)
                                    .font(.body.weight(.medium))
                                Text(occurrence.startDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
