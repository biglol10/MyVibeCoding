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

        let current = numericValue(description[kIOPSCurrentCapacityKey as String])
        let maximum = numericValue(description[kIOPSMaxCapacityKey as String])
        let percentage: Double? = {
            guard let current, let maximum, maximum > 0 else { return nil }
            return (current / maximum) * 100
        }()
        let healthText = description[kIOPSBatteryHealthKey as String] as? String
            ?? description["BatteryHealth"] as? String
            ?? ""
        let serviceRecommended = healthText.localizedCaseInsensitiveContains("service")
            || healthText.localizedCaseInsensitiveContains("replace")

        return BatterySnapshot(
            isPresent: true,
            percentage: percentage,
            isCharging: description[kIOPSIsChargingKey as String] as? Bool,
            powerSource: description[kIOPSPowerSourceStateKey as String] as? String ?? powerSource,
            timeRemainingMinutes: description[kIOPSTimeToEmptyKey as String] as? Int,
            cycleCount: description["Cycle Count"] as? Int,
            serviceRecommended: serviceRecommended
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

    private func numericValue(_ value: Any?) -> Double? {
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
