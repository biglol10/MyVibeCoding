import SwiftData
import SwiftUI
import MyMacCalendarCore

struct QuickAddView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var parsed: QuickAddResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("빠른 추가")
                    .font(.headline.weight(.bold))
                Text("예: 6/30 codex 만료")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 14) {
                TextField("날짜와 제목을 입력", text: $input)
                    .font(.system(size: 16, weight: .medium))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: input) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        parsed = trimmed.isEmpty ? nil : QuickAddParser().parse(newValue)
                    }
                    .onSubmit(parse)

                if let parsed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("미리보기")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(parsed.title)
                            .font(.subheadline.weight(.bold))
                        Text(parsed.startDate.formatted(date: .complete, time: .omitted))
                            .foregroundStyle(.secondary)
                        if parsed.needsConfirmation {
                            Label("날짜 확인이 필요합니다.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.18)))
                } else {
                    Text("입력하면 날짜와 제목을 분석해서 저장 전에 보여줍니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)

            Divider()
            HStack {
                Spacer()
                Button("취소") { dismiss() }
                Button("추가") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(parsed == nil)
            }
            .padding(18)
        }
        .frame(width: 460)
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
