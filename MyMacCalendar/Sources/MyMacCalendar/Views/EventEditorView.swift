import SwiftData
import SwiftUI
import MyMacCalendarCore

private enum DateSelectionRole: String, CaseIterable, Identifiable {
    case start
    case end

    var id: String { rawValue }

    var title: String {
        switch self {
        case .start:
            return "시작일"
        case .end:
            return "종료일"
        }
    }
}

struct EventEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let event: CalendarEvent?
    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var category: EventCategory
    @State private var notes: String
    @State private var recurrence: EventRecurrence
    @State private var notificationOffsets: Set<Int>
    @State private var dateSelectionRole: DateSelectionRole
    @State private var displayedDateMonth: Date
    @State private var showingDeleteConfirmation = false

    init(event: CalendarEvent? = nil, defaultDate: Date = Date()) {
        self.event = event
        let initialDate = event?.startDate ?? defaultDate
        _title = State(initialValue: event?.title ?? "")
        _startDate = State(initialValue: initialDate)
        _endDate = State(initialValue: event?.endDate ?? initialDate)
        _category = State(initialValue: event?.category ?? .personal)
        _notes = State(initialValue: event?.notes ?? "")
        _recurrence = State(initialValue: event?.recurrence ?? .none)
        _notificationOffsets = State(initialValue: Set(event?.notificationOffsetsDays ?? [1]))
        _dateSelectionRole = State(initialValue: .start)
        _displayedDateMonth = State(initialValue: initialDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            HStack(alignment: .top, spacing: 22) {
                formColumn
                    .frame(width: 370, alignment: .topLeading)

                dateColumn
                    .frame(width: 330, alignment: .topLeading)
            }
            .padding(22)

            Divider()

            footer
        }
        .frame(width: 770)
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog("이 일정을 삭제할까요?", isPresented: $showingDeleteConfirmation) {
            Button("삭제", role: .destructive) { delete() }
            Button("취소", role: .cancel) {}
        } message: {
            Text(recurrence == .none ? "이 일정이 삭제됩니다." : "반복 일정 전체가 삭제됩니다.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(event == nil ? "새 일정" : "일정 편집")
                    .font(.system(size: 18, weight: .bold))
                Text("하루종일 일정 · \(dateRangeSummary)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.52))
    }

    private var formColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            editorSection("기본 정보") {
                TextField("일정 제목", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(inputBackground)
                    .overlay(inputStroke)

                Picker("카테고리", selection: $category) {
                    ForEach(EventCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.segmented)

                Picker("반복", selection: $recurrence) {
                    Text("없음").tag(EventRecurrence.none)
                    Text("매주").tag(EventRecurrence.weekly)
                    Text("매월").tag(EventRecurrence.monthly)
                    Text("매년").tag(EventRecurrence.yearly)
                }
                .pickerStyle(.segmented)
            }

            editorSection("알림") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach([7, 2, 1, 0], id: \.self) { offset in
                        ReminderChip(
                            title: label(for: offset),
                            isSelected: notificationOffsets.contains(offset)
                        ) {
                            toggleReminder(offset)
                        }
                    }
                }
            }

            editorSection("메모") {
                TextEditor(text: $notes)
                    .font(.system(size: 13))
                    .frame(height: 116)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(inputBackground)
                    .overlay(inputStroke)
            }
        }
    }

    private var dateColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("날짜")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("오늘") {
                    let today = Calendar.current.startOfDay(for: Date())
                    startDate = today
                    endDate = today
                    displayedDateMonth = today
                    dateSelectionRole = .start
                }
                .font(.system(size: 12, weight: .semibold))
            }

            HStack(spacing: 8) {
                DateSummaryButton(
                    title: "시작",
                    dateText: formattedDate(startDate),
                    isActive: dateSelectionRole == .start
                ) {
                    dateSelectionRole = .start
                    displayedDateMonth = startDate
                }

                DateSummaryButton(
                    title: "종료",
                    dateText: formattedDate(endDate),
                    isActive: dateSelectionRole == .end
                ) {
                    dateSelectionRole = .end
                    displayedDateMonth = endDate
                }
            }

            Picker("선택할 날짜", selection: $dateSelectionRole) {
                ForEach(DateSelectionRole.allCases) { role in
                    Text(role.title).tag(role)
                }
            }
            .pickerStyle(.segmented)

            EventDateGridView(
                displayedMonth: $displayedDateMonth,
                startDate: $startDate,
                endDate: $endDate,
                activeRole: $dateSelectionRole,
                selectDate: selectDate(_:)
            )

            Text("달력에서 날짜를 클릭하면 \(dateSelectionRole.title)이 바로 바뀝니다.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var footer: some View {
        HStack {
            if event != nil {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("삭제", systemImage: "trash")
                }
            }
            Spacer()
            Button("취소") { dismiss() }
            Button("저장") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(18)
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
    }

    private var inputStroke: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.white.opacity(0.14), lineWidth: 1)
    }

    private var dateRangeSummary: String {
        if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            return formattedDate(startDate)
        }
        return "\(formattedDate(startDate)) - \(formattedDate(endDate))"
    }

    private func editorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: date)
    }

    private func selectDate(_ date: Date) {
        let selected = Calendar.current.startOfDay(for: date)
        switch dateSelectionRole {
        case .start:
            startDate = selected
            if endDate < selected {
                endDate = selected
            }
            dateSelectionRole = .end
        case .end:
            if selected < startDate {
                startDate = selected
            }
            endDate = max(selected, startDate)
        }
        displayedDateMonth = selected
    }

    private func toggleReminder(_ offset: Int) {
        if notificationOffsets.contains(offset) {
            notificationOffsets.remove(offset)
        } else {
            notificationOffsets.insert(offset)
        }
    }

    private func label(for offset: Int) -> String {
        switch offset {
        case 0:
            return "당일"
        case 1:
            return "하루 전"
        default:
            return "\(offset)일 전"
        }
    }

    private func save() {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedStart = Calendar.current.startOfDay(for: startDate)
        let normalizedEnd = Calendar.current.startOfDay(for: max(endDate, startDate))

        if let event {
            event.title = normalizedTitle
            event.startDate = normalizedStart
            event.endDate = normalizedEnd
            event.category = category
            event.colorHex = category.colorHex
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
                    colorHex: category.colorHex,
                    category: category,
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

private struct DateSummaryButton: View {
    let title: String
    let dateText: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(dateText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isActive ? Color.accentColor.opacity(0.24) : Color(nsColor: .textBackgroundColor).opacity(0.52))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isActive ? Color.accentColor.opacity(0.72) : Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ReminderChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor).opacity(0.55))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EventDateGridView: View {
    @Binding var displayedMonth: Date
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var activeRole: DateSelectionRole
    let selectDate: (Date) -> Void

    private let calendar = Calendar.current
    private let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    moveMonth(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text(monthTitle)
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)

                Button {
                    moveMonth(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(index == 0 ? AppTheme.sundayText : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 18)
                }

                ForEach(cells, id: \.date) { cell in
                    dayButton(cell)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var cells: [CalendarDayCell] {
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        return (try? CalendarGridBuilder().makeMonthGrid(year: components.year ?? 2026, month: components.month ?? 1)) ?? []
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: displayedMonth)
    }

    private func dayButton(_ cell: CalendarDayCell) -> some View {
        let isEndpoint = calendar.isDate(cell.date, inSameDayAs: startDate) || calendar.isDate(cell.date, inSameDayAs: endDate)
        let isActiveDate = calendar.isDate(cell.date, inSameDayAs: activeRole == .start ? startDate : endDate)
        let isInRange = calendar.startOfDay(for: startDate) <= cell.date && cell.date <= calendar.startOfDay(for: endDate)

        return Button {
            selectDate(cell.date)
        } label: {
            Text("\(cell.day)")
                .font(.system(size: 13, weight: isEndpoint ? .bold : .semibold))
                .foregroundStyle(dayColor(for: cell, isEndpoint: isEndpoint))
                .frame(maxWidth: .infinity)
                .frame(height: 31)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(dayBackground(isEndpoint: isEndpoint, isInRange: isInRange))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(dayBorder(cell: cell, isActiveDate: isActiveDate), lineWidth: isActiveDate ? 1.5 : 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(cell.isInDisplayedMonth ? 1 : 0.42)
    }

    private func dayColor(for cell: CalendarDayCell, isEndpoint: Bool) -> Color {
        if isEndpoint {
            return .white
        }
        if cell.isSunday {
            return AppTheme.sundayText
        }
        if cell.isInDisplayedMonth == false {
            return AppTheme.mutedText
        }
        return AppTheme.primaryText
    }

    private func dayBackground(isEndpoint: Bool, isInRange: Bool) -> Color {
        if isEndpoint {
            return Color.accentColor
        }
        if isInRange {
            return Color.accentColor.opacity(0.20)
        }
        return Color.clear
    }

    private func dayBorder(cell: CalendarDayCell, isActiveDate: Bool) -> Color {
        if isActiveDate {
            return Color.white.opacity(0.7)
        }
        if cell.isToday {
            return AppTheme.todayRed.opacity(0.72)
        }
        return Color.clear
    }

    private func moveMonth(_ value: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
    }
}
