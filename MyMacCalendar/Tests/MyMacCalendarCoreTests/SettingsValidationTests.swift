import SwiftData
import XCTest
@testable import MyMacCalendarCore

final class SettingsValidationTests: XCTestCase {
    func testVisibleCountNormalization() {
        XCTAssertEqual(SettingsValidation.visibleCount(-4), 3)
        XCTAssertEqual(SettingsValidation.visibleCount(0), 3)
        XCTAssertEqual(SettingsValidation.visibleCount(5), 5)
        XCTAssertEqual(SettingsValidation.visibleCount(500), 12)
    }

    func testOpacityNormalizationRejectsNonFiniteAndClampsBounds() {
        XCTAssertEqual(SettingsValidation.opacity(.nan), 0.96)
        XCTAssertEqual(SettingsValidation.opacity(.infinity), 0.96)
        XCTAssertEqual(SettingsValidation.opacity(-.infinity), 0.96)
        XCTAssertEqual(SettingsValidation.opacity(0.1), 0.4)
        XCTAssertEqual(SettingsValidation.opacity(0.75), 0.75)
        XCTAssertEqual(SettingsValidation.opacity(2.0), 1.0)
    }

    func testOpacityPercentIsSafeForEveryDoubleClass() {
        XCTAssertEqual(SettingsValidation.opacityPercent(.nan), 96)
        XCTAssertEqual(SettingsValidation.opacityPercent(.infinity), 96)
        XCTAssertEqual(SettingsValidation.opacityPercent(-.infinity), 96)
        XCTAssertEqual(SettingsValidation.opacityPercent(0.756), 76)
    }

    func testReminderTimeThemeAndDensityNormalization() {
        XCTAssertEqual(SettingsValidation.reminderHour(-1), 0)
        XCTAssertEqual(SettingsValidation.reminderHour(23), 23)
        XCTAssertEqual(SettingsValidation.reminderHour(24), 23)
        XCTAssertEqual(SettingsValidation.reminderMinute(-1), 0)
        XCTAssertEqual(SettingsValidation.reminderMinute(59), 59)
        XCTAssertEqual(SettingsValidation.reminderMinute(60), 59)
        XCTAssertEqual(SettingsValidation.theme("dark"), "dark")
        XCTAssertEqual(SettingsValidation.theme("damaged"), "system")
        XCTAssertEqual(SettingsValidation.density("compact"), "compact")
        XCTAssertEqual(SettingsValidation.density("damaged"), "comfortable")
    }

    func testRepairSaveFailureRollbackStillProducesSafeRenderSnapshot() throws {
        let container = try CalendarStore.makeInMemoryContainer()
        let context = ModelContext(container)
        let damaged = AppSettings(
            floatingWidgetOpacity: 0.1,
            floatingWidgetVisibleCount: -10,
            defaultReminderHour: 90,
            defaultReminderMinute: -3,
            theme: "corrupt",
            calendarDensity: "corrupt"
        )
        context.insert(damaged)
        try context.save()

        let store = SettingsStore(
            context: context,
            saveTransaction: { context in
                context.rollback()
                throw RepairSaveError.failed
            }
        )

        XCTAssertThrowsError(try store.load())
        let rolledBack = try XCTUnwrap(context.fetch(FetchDescriptor<AppSettings>()).first)
        XCTAssertEqual(rolledBack.floatingWidgetOpacity, 0.1)

        let render = SettingsValidation.snapshot(rolledBack)
        XCTAssertEqual(render.floatingWidgetOpacity, 0.4)
        XCTAssertEqual(render.floatingWidgetVisibleCount, 3)
        XCTAssertEqual(render.defaultReminderHour, 23)
        XCTAssertEqual(render.defaultReminderMinute, 0)
        XCTAssertEqual(render.theme, "system")
        XCTAssertEqual(render.calendarDensity, "comfortable")
        XCTAssertEqual(SettingsValidation.opacityPercent(rolledBack.floatingWidgetOpacity), 40)
    }

    func testNonFiniteValueReexposedAfterFailedRepairStillRendersSafely() {
        let damaged = AppSettings(floatingWidgetOpacity: .nan)
        XCTAssertTrue(SettingsValidation.repair(damaged))
        XCTAssertEqual(damaged.floatingWidgetOpacity, 0.96)

        damaged.floatingWidgetOpacity = .nan

        XCTAssertEqual(SettingsValidation.snapshot(damaged).floatingWidgetOpacity, 0.96)
        XCTAssertEqual(SettingsValidation.opacityPercent(damaged.floatingWidgetOpacity), 96)
    }
}

private enum RepairSaveError: Error {
    case failed
}
