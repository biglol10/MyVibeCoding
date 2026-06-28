import Foundation

public enum UsageChartScaling {
    public struct Row: Equatable {
        public let id: UUID
        public let name: String
        public let category: ActivityCategory
        public let durationSeconds: Int
        public let relativeWidth: Double

        public init(
            id: UUID,
            name: String,
            category: ActivityCategory,
            durationSeconds: Int,
            relativeWidth: Double
        ) {
            self.id = id
            self.name = name
            self.category = category
            self.durationSeconds = durationSeconds
            self.relativeWidth = relativeWidth
        }
    }

    public static func rows(items: [UsageItem], limit: Int) -> [Row] {
        let limited = Array(items.prefix(max(0, limit)))
        let maxDuration = limited.map(\.durationSeconds).max() ?? 0

        return limited.map { item in
            Row(
                id: item.id,
                name: item.name,
                category: item.category,
                durationSeconds: item.durationSeconds,
                relativeWidth: maxDuration > 0 ? Double(item.durationSeconds) / Double(maxDuration) : 0
            )
        }
    }
}
