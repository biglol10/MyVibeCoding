import XCTest
import IOKit.ps
@testable import MyMacStatsCore

final class BatterySamplerTests: XCTestCase {
    func testChargingUsesTimeUntilFullInsteadOfTimeUntilEmpty() {
        let battery = sample([
            kIOPSIsChargingKey: true,
            kIOPSTimeToEmptyKey: 0,
            kIOPSTimeToFullChargeKey: 42
        ])
        XCTAssertNil(battery.timeRemainingMinutes)
        XCTAssertEqual(battery.timeToFullChargeMinutes, 42)
        XCTAssertEqual(battery.timeEstimateTitle, "Time Until Full")
        XCTAssertEqual(battery.timeEstimateText, "42m")
    }

    func testCalculatingAndExternalPowerDoNotShowInvalidMinutes() {
        let calculating = sample([kIOPSIsChargingKey: true, kIOPSTimeToFullChargeKey: -1])
        XCTAssertNil(calculating.timeToFullChargeMinutes)
        XCTAssertEqual(calculating.timeEstimateText, "Calculating…")
        let external = sample([kIOPSIsChargingKey: false, kIOPSTimeToEmptyKey: 0])
        XCTAssertNil(external.timeRemainingMinutes)
        XCTAssertEqual(external.timeEstimateText, "On external power")
        let full = sample([kIOPSIsChargedKey: true, kIOPSTimeToEmptyKey: 0])
        XCTAssertEqual(full.timeEstimateText, "Fully charged")
    }

    func testDischargingUsesValidTimeToEmptyOnly() {
        let battery = sample([
            kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
            kIOPSIsChargingKey: false,
            kIOPSTimeToEmptyKey: 75,
            kIOPSTimeToFullChargeKey: 10
        ])
        XCTAssertEqual(battery.timeRemainingMinutes, 75)
        XCTAssertNil(battery.timeToFullChargeMinutes)
        XCTAssertEqual(battery.timeEstimateText, "75m")
    }

    func testPoorHealthAndRepairConditionsRecommendService() {
        let fixtures: [[String: Any]] = [
            [kIOPSBatteryHealthKey: kIOPSPoorValue],
            [kIOPSBatteryHealthKey: kIOPSGoodValue, kIOPSBatteryHealthConditionKey: kIOPSCheckBatteryValue],
            [kIOPSBatteryHealthConditionKey: kIOPSPermanentFailureValue]
        ]
        for values in fixtures {
            let battery = sample(values)
            XCTAssertTrue(battery.serviceRecommended)
            XCTAssertEqual(battery.serviceStatusText, "Recommended")
        }
    }

    func testMissingHealthIsNotReportedAsOK() {
        XCTAssertEqual(sample([:]).serviceStatusText, "Unavailable")
        XCTAssertEqual(sample([kIOPSBatteryHealthKey: kIOPSGoodValue]).serviceStatusText, "OK")
        XCTAssertEqual(sample([kIOPSBatteryHealthKey: kIOPSFairValue]).serviceStatusText, "Limited capacity")
    }

    private func sample(_ values: [String: Any]) -> BatterySnapshot {
        BatterySampler.snapshot(from: values, powerSource: kIOPSACPowerValue)
    }
}
