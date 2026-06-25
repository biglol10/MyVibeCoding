import SwiftData
import SwiftUI
import MyMacCalendarCore

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRows: [AppSettings]
    @Query(sort: \HolidayRecord.date) private var holidays: [HolidayRecord]
    @State private var selectedTab = "general"
    @State private var newHolidayTitle = ""
    @State private var newHolidayDate = Date()

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            widgetTab
                .tabItem { Label("Widget", systemImage: "rectangle.on.rectangle") }
                .tag("widget")
            notificationsTab
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag("notifications")
            holidaysTab
                .tabItem { Label("Holidays", systemImage: "calendar.badge.exclamationmark") }
                .tag("holidays")
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag("appearance")
            dataTab
                .tabItem { Label("Data", systemImage: "externaldrive") }
                .tag("data")
        }
        .padding(20)
        .frame(width: 680, height: 480)
        .onAppear { ensureSettings() }
    }

    private var settings: AppSettings {
        if let existing = settingsRows.first { return existing }
        let created = AppSettings()
        modelContext.insert(created)
        return created
    }

    private var generalTab: some View {
        Form {
            Toggle("Mac start auto-run", isOn: binding(\.launchAtLogin))
            Toggle("Show menu bar icon", isOn: binding(\.showMenuBar))
        }
        .padding()
    }

    private var widgetTab: some View {
        Form {
            Toggle("Show floating widget", isOn: binding(\.floatingWidgetEnabled))
            Toggle("Always on top", isOn: binding(\.floatingWidgetAlwaysOnTop))
            Slider(value: binding(\.floatingWidgetOpacity), in: 0.4...1.0) {
                Text("Opacity")
            }
            Stepper("Visible events: \(settings.floatingWidgetVisibleCount)", value: binding(\.floatingWidgetVisibleCount), in: 1...12)
        }
        .padding()
    }

    private var notificationsTab: some View {
        Form {
            Stepper("Hour: \(settings.defaultReminderHour)", value: binding(\.defaultReminderHour), in: 0...23)
            Stepper("Minute: \(settings.defaultReminderMinute)", value: binding(\.defaultReminderMinute), in: 0...59)
        }
        .padding()
    }

    private var holidaysTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DatePicker("Date", selection: $newHolidayDate, displayedComponents: .date)
                TextField("Holiday name", text: $newHolidayTitle)
                    .textFieldStyle(.roundedBorder)
                Button("Add") { addManualHoliday() }
                    .disabled(newHolidayTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            List {
                ForEach(holidays.filter { $0.isHidden == false }, id: \.id) { holiday in
                    HStack {
                        Text(holiday.date.formatted(date: .abbreviated, time: .omitted))
                            .frame(width: 100, alignment: .leading)
                        Text(holiday.title)
                        Spacer()
                        Text(holiday.source.rawValue.uppercased())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            hideOrDelete(holiday)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding()
    }

    private var appearanceTab: some View {
        Form {
            Picker("Theme", selection: binding(\.theme)) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            Picker("Calendar density", selection: binding(\.calendarDensity)) {
                Text("Comfortable").tag("comfortable")
                Text("Compact").tag("compact")
            }
        }
        .padding()
    }

    private var dataTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data is stored locally using SwiftData.")
            Text("Backup and restore are reserved for a later version.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }

    private func ensureSettings() {
        if settingsRows.isEmpty {
            modelContext.insert(AppSettings())
            try? modelContext.save()
        }
    }

    private func addManualHoliday() {
        let normalizedTitle = newHolidayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Calendar.current.component(.year, from: newHolidayDate)
        modelContext.insert(HolidayRecord(date: Calendar.current.startOfDay(for: newHolidayDate), title: normalizedTitle, source: .manual, year: year))
        newHolidayTitle = ""
        try? modelContext.save()
    }

    private func hideOrDelete(_ holiday: HolidayRecord) {
        if holiday.source == .api {
            holiday.isHidden = true
        } else {
            modelContext.delete(holiday)
        }
        try? modelContext.save()
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: {
                settings[keyPath: keyPath] = $0
                try? modelContext.save()
            }
        )
    }
}
