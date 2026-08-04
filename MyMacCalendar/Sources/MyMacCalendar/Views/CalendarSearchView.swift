import SwiftUI
import MyMacCalendarCore

struct CalendarSearchField: View {
    @Binding var query: String
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)

            TextField("검색", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.primaryText)
                .focused(isFocused)
                .onExitCommand {
                    if query.isEmpty {
                        isFocused.wrappedValue = false
                    } else {
                        query = ""
                    }
                }

            Group {
                if query.isEmpty {
                    Color.clear
                } else {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help("검색어 지우기")
                    .accessibilityLabel("검색어 지우기")
                }
            }
            .frame(width: 16, height: 16)
        }
        .padding(.horizontal, 10)
        .frame(width: 220, height: 32)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(isFocused.wrappedValue ? Color.accentColor.opacity(0.82) : Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}

struct CalendarSearchResultsView: View {
    let query: String
    let events: [CalendarEvent]
    let onClear: () -> Void
    let onSelect: (CalendarEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                if events.isEmpty {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(events, id: \.id) { event in
                            resultRow(event)
                            Divider()
                                .overlay(AppTheme.gridLine)
                        }
                    }
                }
            }
        }
        .background(Color(red: 0.10, green: 0.095, blue: 0.095))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("검색 결과")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 26)
                }
                .buttonStyle(.plain)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .help("검색 닫기")
                .accessibilityLabel("검색 닫기")
            }

            Text("\(events.count)개 일정 · \(query.trimmingCharacters(in: .whitespacesAndNewlines))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(18)
        .background(AppTheme.headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.gridLine)
                .frame(height: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
            Text("검색 결과 없음")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Text("다른 제목이나 메모를 검색해 보세요.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.mutedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 52)
    }

    private func resultRow(_ event: CalendarEvent) -> some View {
        Button {
            onSelect(event)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: event.colorHex))
                    .frame(width: 4, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(metadata(for: event))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if notesPreview(for: event).isEmpty == false {
                        Text(notesPreview(for: event))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.mutedText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("일정 편집")
    }

    private func metadata(for event: CalendarEvent) -> String {
        var parts = [
            event.startDate.formatted(date: .abbreviated, time: .omitted),
            event.category.title
        ]
        if event.recurrence != .none {
            parts.append(recurrenceTitle(event.recurrence))
        }
        return parts.joined(separator: " · ")
    }

    private func notesPreview(for event: CalendarEvent) -> String {
        event.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func recurrenceTitle(_ recurrence: EventRecurrence) -> String {
        switch recurrence {
        case .none:
            return ""
        case .weekly:
            return "매주"
        case .monthly:
            return "매월"
        case .yearly:
            return "매년"
        }
    }
}
