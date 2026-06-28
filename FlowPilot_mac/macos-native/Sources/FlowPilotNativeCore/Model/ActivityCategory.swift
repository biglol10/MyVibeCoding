import SwiftUI

public enum ActivityCategory: String, CaseIterable, Identifiable, Equatable {
    case productive
    case unproductive
    case neutral
    case ignored
    case uncategorized
    case idle

    public var id: String { rawValue }

    public init(databaseValue: String, isIdle: Bool = false) {
        if isIdle {
            self = .idle
            return
        }

        switch databaseValue {
        case "productive": self = .productive
        case "unproductive": self = .unproductive
        case "neutral": self = .neutral
        case "ignored": self = .ignored
        case "uncategorized": self = .uncategorized
        default: self = .uncategorized
        }
    }

    public var koreanLabel: String {
        switch self {
        case .productive: return "생산적"
        case .unproductive: return "비생산"
        case .neutral: return "중립"
        case .ignored: return "제외"
        case .uncategorized: return "검토 필요"
        case .idle: return "유휴"
        }
    }

    public var databaseValue: String {
        switch self {
        case .productive: return "productive"
        case .unproductive: return "unproductive"
        case .neutral: return "neutral"
        case .ignored: return "ignored"
        case .uncategorized: return "uncategorized"
        case .idle: return "idle"
        }
    }

    public static var ruleAssignableCases: [ActivityCategory] {
        [.productive, .unproductive, .neutral, .ignored]
    }

    public var color: Color {
        switch self {
        case .productive: return .green
        case .unproductive: return .red
        case .neutral: return .blue
        case .ignored: return .gray
        case .uncategorized: return .purple
        case .idle: return .secondary
        }
    }
}
