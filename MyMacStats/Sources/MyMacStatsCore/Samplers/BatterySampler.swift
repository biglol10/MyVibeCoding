import Foundation
import IOKit.ps

public struct BatterySampler {
    public init() {}

    public func sample() throws -> BatterySnapshot {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return desktopSnapshot(powerSource: "Unknown")
        }

        let powerSource = IOPSGetProvidingPowerSourceType(info)?.takeRetainedValue() as String? ?? "Unknown"
        guard let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return desktopSnapshot(powerSource: powerSource)
        }

        return Self.snapshot(from: description, powerSource: powerSource)
    }

    static func snapshot(from description: [String: Any], powerSource: String) -> BatterySnapshot {
        let current = numericValue(description[kIOPSCurrentCapacityKey as String])
        let maximum = numericValue(description[kIOPSMaxCapacityKey as String])
        let percentage: Double? = {
            guard let current, let maximum, current.isFinite, maximum.isFinite, current >= 0, maximum > 0 else { return nil }
            return min(100, (current / maximum) * 100)
        }()
        let healthText = description[kIOPSBatteryHealthKey as String] as? String ?? ""
        let condition = description[kIOPSBatteryHealthConditionKey as String] as? String ?? ""
        let serviceRecommended = healthText == kIOPSPoorValue
            || condition == kIOPSCheckBatteryValue
            || condition == kIOPSPermanentFailureValue
            || [healthText, condition].contains { $0.localizedCaseInsensitiveContains("service") || $0.localizedCaseInsensitiveContains("replace") }
        let healthDescription: String? = healthText == kIOPSGoodValue ? "OK"
            : healthText == kIOPSFairValue ? "Limited capacity" : nil
        let charging = description[kIOPSIsChargingKey as String] as? Bool
        let source = description[kIOPSPowerSourceStateKey as String] as? String ?? powerSource
        let fullyCharged = description[kIOPSIsChargedKey as String] as? Bool ?? false
        let timeKey = charging == true ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        let rawMinutes = description[timeKey as String] as? Int
        let canEstimate = charging == true || (source == kIOPSBatteryPowerValue && charging == false)
        let minutes = canEstimate ? rawMinutes.flatMap { $0 >= 0 ? $0 : nil } : nil

        return BatterySnapshot(
            isPresent: true,
            percentage: percentage,
            isCharging: charging,
            powerSource: source,
            timeRemainingMinutes: charging == false ? minutes : nil,
            cycleCount: description["Cycle Count"] as? Int,
            serviceRecommended: serviceRecommended,
            timeToFullChargeMinutes: charging == true ? minutes : nil,
            isFullyCharged: fullyCharged,
            isCalculatingTime: canEstimate && rawMinutes == -1,
            healthDescription: healthDescription
        )
    }

    private func desktopSnapshot(powerSource: String) -> BatterySnapshot {
        BatterySnapshot(
            isPresent: false,
            percentage: nil,
            isCharging: nil,
            powerSource: powerSource,
            timeRemainingMinutes: nil,
            cycleCount: nil,
            serviceRecommended: false
        )
    }

    private static func numericValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        return nil
    }
}
