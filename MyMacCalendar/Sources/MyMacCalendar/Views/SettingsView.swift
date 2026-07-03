import SwiftData
import SwiftUI
import MyMacCalendarCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \HolidayRecord.date) private var holidays: [HolidayRecord]
    @State private var selectedTab = "general"
    @State private var newHolidayTitle = ""
    @State private var newHolidayDate = Date()
    @State private var settingsErrorMessage: String?
    @State private var isFetchingHolidays = false
    @State private var holidayFetchMessage: String?
    @State private var floatingWidgetOpacityDraft: Double?

    private let reminderPresets = [
        ReminderTimePreset(hour: 8, minute: 0),
        ReminderTimePreset(hour: 9, minute: 0),
        ReminderTimePreset(hour: 10, minute: 0),
        ReminderTimePreset(hour: 18, minute: 0)
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                generalTab
                    .tabItem { Label("일반", systemImage: "gearshape") }
                    .tag("general")
                widgetTab
                    .tabItem { Label("위젯", systemImage: "rectangle.on.rectangle") }
                    .tag("widget")
                notificationsTab
                    .tabItem { Label("알림", systemImage: "bell") }
                    .tag("notifications")
                holidaysTab
                    .tabItem { Label("휴일", systemImage: "calendar.badge.exclamationmark") }
                    .tag("holidays")
                appearanceTab
                    .tabItem { Label("화면", systemImage: "paintpalette") }
                    .tag("appearance")
                dataTab
                    .tabItem { Label("데이터", systemImage: "externaldrive") }
                    .tag("data")
            }

            Divider()

            HStack {
                Spacer()
                Button("완료") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 760, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { ensureSettings() }
        .alert("설정을 적용할 수 없습니다", isPresented: settingsErrorBinding) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(settingsErrorMessage ?? "다시 시도해 주세요.")
        }
    }

    private var settings: AppSettings {
        if let existing = settingsRows.first { return existing }
        let created = AppSettings()
        modelContext.insert(created)
        return created
    }

    private var generalTab: some View {
        SettingsPage {
            SettingsSection("앱") {
                SettingsRow("Mac 시작 시 자동 실행") {
                    Toggle("", isOn: launchAtLoginBinding)
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsRow("메뉴 막대 아이콘 표시") {
                    Toggle("", isOn: binding(\.showMenuBar))
                        .labelsHidden()
                }
            }
        }
    }

    private var widgetTab: some View {
        SettingsPage {
            SettingsSection("다가오는 일정 박스") {
                SettingsRow("플로팅 위젯 표시") {
                    Toggle("", isOn: binding(\.floatingWidgetEnabled))
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsRow("항상 위에 표시") {
                    Toggle("", isOn: binding(\.floatingWidgetAlwaysOnTop))
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsRow("투명도") {
                    HStack(spacing: 12) {
                        Slider(
                            value: floatingWidgetOpacityDraftBinding,
                            in: 0.4...1.0,
                            onEditingChanged: handleFloatingWidgetOpacityEditingChanged
                        )
                            .frame(width: SettingsLayout.compactSliderWidth)
                        Text(opacityPercentText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                }
                SettingsDivider()
                SettingsRow("표시할 일정 수") {
                    Picker("", selection: binding(\.floatingWidgetVisibleCount)) {
                        Text("3개").tag(3)
                        Text("5개").tag(5)
                        Text("8개").tag(8)
                        Text("12개").tag(12)
                    }
                    .labelsHidden()
                    .frame(width: 116)
                }
            }
        }
    }

    private var notificationsTab: some View {
        SettingsPage {
            SettingsSection("기본 알림 시간") {
                SettingsRow("빠른 선택") {
                    HStack(spacing: 8) {
                        ForEach(reminderPresets) { preset in
                            ReminderTimePresetButton(
                                title: preset.title,
                                isSelected: settings.defaultReminderHour == preset.hour &&
                                    settings.defaultReminderMinute == preset.minute
                            ) {
                                setReminderTime(hour: preset.hour, minute: preset.minute)
                            }
                        }
                    }
                }
                SettingsDivider()
                SettingsRow("직접 입력") {
                    DatePicker("", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .frame(width: 110, alignment: .leading)
                }
            }
        }
    }

    private var holidaysTab: some View {
        SettingsPage {
            SettingsSection("휴일 추가") {
                SettingsRow("날짜") {
                    DatePicker("", selection: $newHolidayDate, displayedComponents: .date)
                        .labelsHidden()
                        .frame(width: 150, alignment: .leading)
                }
                SettingsDivider()
                SettingsRow("이름") {
                    HStack(spacing: 10) {
                        TextField("휴일 이름", text: $newHolidayTitle)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                        Button("추가") { addManualHoliday() }
                            .disabled(newHolidayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                SettingsDivider()
                SettingsRow("온라인") {
                    HStack(spacing: 10) {
                        Button(isFetchingHolidays ? "가져오는 중..." : "한국 휴일 가져오기") {
                            fetchOnlineHolidays()
                        }
                        .disabled(isFetchingHolidays)

                        if let holidayFetchMessage {
                            Text(holidayFetchMessage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            SettingsSection("등록된 휴일") {
                if visibleHolidays.isEmpty {
                    SettingsEmptyRow("등록된 휴일 없음")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(visibleHolidays.enumerated()), id: \.element.id) { index, holiday in
                            HolidaySettingsRow(holiday: holiday) {
                                hideOrDelete(holiday)
                            }
                            if index < visibleHolidays.count - 1 {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }
        }
    }

    private var appearanceTab: some View {
        SettingsPage {
            SettingsSection("달력") {
                SettingsRow("달력 밀도") {
                    Picker("", selection: binding(\.calendarDensity)) {
                        Text("여유 있게").tag("comfortable")
                        Text("촘촘하게").tag("compact")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }
            }
        }
    }

    private var dataTab: some View {
        SettingsPage {
            SettingsSection("데이터") {
                SettingsEmptyRow("데이터는 이 Mac에 로컬로 저장됩니다.")
                SettingsDivider()
                SettingsEmptyRow("백업과 복원 기능은 이후 버전에서 추가할 수 있습니다.")
            }
        }
    }

    private var visibleHolidays: [HolidayRecord] {
        holidays.filter { $0.isHidden == false }
    }

    private var opacityPercentText: String {
        "\(Int((floatingWidgetOpacityValue * 100).rounded()))%"
    }

    private var floatingWidgetOpacityValue: Double {
        floatingWidgetOpacityDraft ?? settings.floatingWidgetOpacity
    }

    private var floatingWidgetOpacityDraftBinding: Binding<Double> {
        Binding(
            get: { floatingWidgetOpacityValue },
            set: { floatingWidgetOpacityDraft = $0 }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                components.hour = settings.defaultReminderHour
                components.minute = settings.defaultReminderMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                setReminderTime(hour: components.hour ?? 9, minute: components.minute ?? 0)
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { setLaunchAtLogin($0) }
        )
    }

    private var settingsErrorBinding: Binding<Bool> {
        Binding(
            get: { settingsErrorMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    settingsErrorMessage = nil
                }
            }
        )
    }

    private func ensureSettings() {
        if settingsRows.isEmpty {
            modelContext.insert(AppSettings())
            saveModelContext("설정을 만들 수 없습니다.")
        }
    }

    private func setReminderTime(hour: Int, minute: Int) {
        settings.defaultReminderHour = min(max(hour, 0), 23)
        settings.defaultReminderMinute = min(max(minute, 0), 59)
        saveModelContext("알림 시간을 저장할 수 없습니다.")
    }

    private func handleFloatingWidgetOpacityEditingChanged(_ isEditing: Bool) {
        if isEditing {
            floatingWidgetOpacityDraft = floatingWidgetOpacityValue
            return
        }
        commitFloatingWidgetOpacity()
    }

    private func commitFloatingWidgetOpacity() {
        guard let draft = floatingWidgetOpacityDraft else { return }
        settings.floatingWidgetOpacity = min(max(draft, 0.4), 1.0)
        floatingWidgetOpacityDraft = nil
        if saveModelContext("위젯 투명도를 저장할 수 없습니다.") {
            notifyAppSettingsChanged()
        }
    }

    private func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try LoginItemController.setEnabled(isEnabled)
            settings.launchAtLogin = isEnabled
            if saveModelContext("자동 실행 설정을 저장할 수 없습니다.") {
                notifyAppSettingsChanged()
            }
        } catch {
            settings.launchAtLogin = false
            saveModelContext("자동 실행 설정을 되돌릴 수 없습니다.")
            settingsErrorMessage = error.localizedDescription
        }
    }

    private func addManualHoliday() {
        let normalizedTitle = newHolidayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Calendar.current.component(.year, from: newHolidayDate)
        modelContext.insert(HolidayRecord(date: Calendar.current.startOfDay(for: newHolidayDate), title: normalizedTitle, source: .manual, year: year))
        newHolidayTitle = ""
        saveModelContext("휴일을 저장할 수 없습니다.")
    }

    private func fetchOnlineHolidays() {
        let year = Calendar.current.component(.year, from: newHolidayDate)
        isFetchingHolidays = true
        holidayFetchMessage = nil

        Task { @MainActor in
            do {
                let imports = try await HolidayService().fetchKoreanHolidays(year: year)
                applyHolidayImports(imports, year: year)
            } catch {
                holidayFetchMessage = "가져오기 실패"
                settingsErrorMessage = error.localizedDescription
                isFetchingHolidays = false
            }
        }
    }

    private func applyHolidayImports(_ imports: [HolidayImport], year: Int) {
        let existingProviderKeys = Set(holidays.filter { $0.source == .api }.map(\.providerKey))
        let merged = HolidayMerger().merge(imports: imports, existing: holidays, year: year)
        let newRecords = merged.filter { holiday in
            holiday.source == .api &&
                holiday.isHidden == false &&
                existingProviderKeys.contains(holiday.providerKey) == false
        }

        for holiday in newRecords {
            modelContext.insert(holiday)
        }

        if saveModelContext("휴일을 저장할 수 없습니다.") {
            holidayFetchMessage = newRecords.isEmpty ? "새 휴일 없음" : "\(newRecords.count)개 추가됨"
        } else {
            holidayFetchMessage = "저장 실패"
        }
        isFetchingHolidays = false
    }

    private func hideOrDelete(_ holiday: HolidayRecord) {
        if holiday.source == .api {
            holiday.isHidden = true
        } else {
            modelContext.delete(holiday)
        }
        saveModelContext("휴일 변경사항을 저장할 수 없습니다.")
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: {
                settings[keyPath: keyPath] = $0
                if saveModelContext("설정을 저장할 수 없습니다.") {
                    notifyAppSettingsChanged()
                }
            }
        )
    }

    @discardableResult
    private func saveModelContext(_ fallbackMessage: String) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            settingsErrorMessage = error.localizedDescription.isEmpty ? fallbackMessage : error.localizedDescription
            return false
        }
    }

    private func notifyAppSettingsChanged() {
        NotificationCenter.default.post(
            name: .appSettingsDidChange,
            object: nil,
            userInfo: [
                "showMenuBar": settings.showMenuBar
            ]
        )
    }
}

private enum SettingsLayout {
    static let contentWidth: CGFloat = 620
    static let labelWidth: CGFloat = 150
    static let compactSliderWidth: CGFloat = 240
    static let rowVerticalPadding: CGFloat = 12
}

private struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content()
            }
            .frame(width: SettingsLayout.contentWidth, alignment: .topLeading)
            .padding(.top, 34)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.50))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: SettingsLayout.labelWidth, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, SettingsLayout.labelWidth + 18)
    }
}

private struct SettingsEmptyRow: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, SettingsLayout.rowVerticalPadding)
    }
}

private struct ReminderTimePreset: Identifiable {
    let hour: Int
    let minute: Int

    var id: String { title }

    var title: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

private struct ReminderTimePresetButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.7))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct HolidaySettingsRow: View {
    let holiday: HolidayRecord
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(holiday.date.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 104, alignment: .leading)

            Text(holiday.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text(holiday.source == .api ? "가져옴" : "수동")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.45))
                .clipShape(Capsule())

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help(holiday.source == .api ? "가져온 휴일 숨기기" : "수동 휴일 삭제")
        }
        .padding(.vertical, 10)
    }
}
