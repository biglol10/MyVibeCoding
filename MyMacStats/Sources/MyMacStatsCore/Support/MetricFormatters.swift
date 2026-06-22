import Foundation

public enum MetricFormatters {
    public static func bytes(_ bytes: UInt64) -> String {
        format(bytes: bytes, units: ["B", "KB", "MB", "GB", "TB", "PB"], separator: " ")
    }

    public static func compactBytes(_ bytes: UInt64) -> String {
        format(bytes: bytes, units: ["B", "K", "M", "G", "T", "P"], separator: "")
    }

    public static func percent(_ value: Double, fractionDigits: Int = 0) -> String {
        let multiplier = pow(10.0, Double(fractionDigits))
        let rounded = (value * multiplier).rounded() / multiplier
        if fractionDigits == 0 {
            return "\(Int(rounded))%"
        }
        return String(format: "%.\(fractionDigits)f%%", rounded)
    }

    public static func speed(_ bytesPerSecond: UInt64) -> String {
        "\(bytes(bytesPerSecond))/s"
    }

    private static func format(bytes: UInt64, units: [String], separator: String) -> String {
        guard bytes >= 1_024 else { return "\(bytes)\(separator)\(units[0])" }

        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1_024, unitIndex < units.count - 1 {
            value /= 1_024
            unitIndex += 1
        }

        let roundedToTenth = (value * 10).rounded() / 10
        let number: String
        if roundedToTenth.rounded() == roundedToTenth {
            number = "\(Int(roundedToTenth))"
        } else {
            number = String(format: "%.1f", roundedToTenth)
        }
        return "\(number)\(separator)\(units[unitIndex])"
    }
}
