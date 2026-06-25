import SwiftUI
import MyMacCalendarCore

struct FloatingWidgetView: View {
    let occurrences: [EventOccurrence]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upcoming")
                .font(.headline)
            if occurrences.isEmpty {
                Text("No upcoming events")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(occurrences, id: \.eventID) { occurrence in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isToday(occurrence) ? Color.red : Color.accentColor)
                            .frame(width: 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(occurrence.title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Text(occurrence.startDate.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func isToday(_ occurrence: EventOccurrence) -> Bool {
        Calendar.current.isDateInToday(occurrence.startDate)
    }
}
