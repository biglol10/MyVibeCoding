import AppKit
import SwiftUI
import MyMacCalendarCore

struct FloatingWidgetView: View {
    let occurrences: [EventOccurrence]
    let onSelect: (EventOccurrence) -> Void
    let onShowAll: () -> Void

    var body: some View {
        let visibleOccurrences = Array(occurrences.prefix(FloatingWidgetConstants.visibleOccurrenceLimit))
        let overflowCount = max(0, occurrences.count - visibleOccurrences.count)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("다가오는 일정")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("\(occurrences.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            if occurrences.isEmpty {
                Text("예정된 일정이 없습니다")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleOccurrences, id: \.eventID) { occurrence in
                    Button { onSelect(occurrence) } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isToday(occurrence) ? Color.red : Color.accentColor)
                                .frame(width: 4, height: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(occurrence.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(occurrence.startDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("일정 상세 보기")
                }

                if overflowCount > 0 {
                    Button { onShowAll() } label: {
                        Text("+\(overflowCount)개")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help("다가오는 일정 전체 보기")
                }
            }
        }
        .padding(16)
        .frame(width: FloatingWidgetConstants.width, height: FloatingWidgetConstants.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.12, green: 0.11, blue: 0.11).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            FloatingWidgetDragHandle()
                .frame(width: FloatingWidgetConstants.width, height: FloatingWidgetConstants.dragHandleHeight)
        }
        .shadow(color: .black.opacity(0.24), radius: 16, x: 0, y: 8)
    }

    private func isToday(_ occurrence: EventOccurrence) -> Bool {
        Calendar.current.isDateInToday(occurrence.startDate)
    }
}

struct FloatingWidgetAllEventsView: View {
    let occurrences: [EventOccurrence]
    let onSelect: (EventOccurrence) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("다가오는 일정")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text("\(occurrences.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(occurrences.enumerated()), id: \.offset) { _, occurrence in
                        Button {
                            onSelect(occurrence)
                        } label: {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(hex: occurrence.colorHex))
                                    .frame(width: 4, height: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(occurrence.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(occurrence.startDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 340, height: 380, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private enum FloatingWidgetConstants {
    static let width: CGFloat = 260
    static let height: CGFloat = 260
    static let visibleOccurrenceLimit = 3
    static let dragHandleHeight: CGFloat = 42
}

private struct FloatingWidgetDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> FloatingWidgetDragHandleView {
        let view = FloatingWidgetDragHandleView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: FloatingWidgetDragHandleView, context: Context) {}
}

private final class FloatingWidgetDragHandleView: NSView {
    private var initialWindowOrigin: NSPoint?
    private var initialMouseLocation: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func mouseDown(with event: NSEvent) {
        initialWindowOrigin = window?.frame.origin
        initialMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let initialWindowOrigin,
              let initialMouseLocation else {
            return
        }

        let currentMouseLocation = NSEvent.mouseLocation
        window.setFrameOrigin(
            NSPoint(
                x: initialWindowOrigin.x + currentMouseLocation.x - initialMouseLocation.x,
                y: initialWindowOrigin.y + currentMouseLocation.y - initialMouseLocation.y
            )
        )
    }
}

struct FloatingEventDetailView: View {
    let event: CalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: event.colorHex))
                    .frame(width: 5, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(2)
                    Text(dateSummary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            detailRow("반복", recurrenceText)
            detailRow("알림", reminderText)

            if event.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    Text("메모")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(event.notes)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(18)
        .frame(width: 320, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var dateSummary: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 (E)"
        if Calendar.current.isDate(event.startDate, inSameDayAs: event.endDate) {
            return formatter.string(from: event.startDate)
        }
        return "\(formatter.string(from: event.startDate)) - \(formatter.string(from: event.endDate))"
    }

    private var recurrenceText: String {
        switch event.recurrence {
        case .none:
            return "없음"
        case .weekly:
            return "매주"
        case .monthly:
            return "매월"
        case .yearly:
            return "매년"
        }
    }

    private var reminderText: String {
        guard event.notificationOffsetsDays.isEmpty == false else { return "없음" }
        return event.notificationOffsetsDays
            .sorted(by: >)
            .map { offset in
                switch offset {
                case 0:
                    return "당일"
                case 1:
                    return "하루 전"
                default:
                    return "\(offset)일 전"
                }
            }
            .joined(separator: ", ")
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}

private extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: value).scanHexInt64(&int)
        self.init(
            red: Double((int >> 16) & 0xFF) / 255.0,
            green: Double((int >> 8) & 0xFF) / 255.0,
            blue: Double(int & 0xFF) / 255.0
        )
    }
}
