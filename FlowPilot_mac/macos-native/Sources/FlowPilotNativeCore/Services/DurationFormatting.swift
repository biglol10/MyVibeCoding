public enum DurationFormatting {
    public static func compact(seconds: Int) -> String {
        if seconds <= 0 {
            return "0m"
        }
        if seconds < 60 {
            return "<1m"
        }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
