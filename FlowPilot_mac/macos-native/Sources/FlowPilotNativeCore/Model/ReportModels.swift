import Foundation

public struct DashboardSummary: Equatable {
    public let totalSeconds: Int
    public let productiveSeconds: Int
    public let unproductiveSeconds: Int
    public let idleSeconds: Int
    public let sessionCount: Int

    public init(
        totalSeconds: Int,
        productiveSeconds: Int,
        unproductiveSeconds: Int,
        idleSeconds: Int,
        sessionCount: Int
    ) {
        self.totalSeconds = totalSeconds
        self.productiveSeconds = productiveSeconds
        self.unproductiveSeconds = unproductiveSeconds
        self.idleSeconds = idleSeconds
        self.sessionCount = sessionCount
    }
}

public struct UsageItem: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let kind: String
    public let category: ActivityCategory
    public let durationSeconds: Int
    public let share: Double
    public let ruleSource: String

    public init(
        id: UUID,
        name: String,
        kind: String,
        category: ActivityCategory,
        durationSeconds: Int,
        share: Double,
        ruleSource: String
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.category = category
        self.durationSeconds = durationSeconds
        self.share = share
        self.ruleSource = ruleSource
    }
}

public struct TimelineSession: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let title: String?
    public let category: ActivityCategory
    public let startedAt: Date
    public let endedAt: Date

    public init(
        id: UUID,
        name: String,
        title: String?,
        category: ActivityCategory,
        startedAt: Date,
        endedAt: Date
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.category = category
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    public var durationSeconds: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }
}

public enum RuleType: String, CaseIterable, Identifiable, Equatable {
    case domain
    case app
    case titleKeyword
    case urlPattern

    public var id: String { rawValue }

    public var koreanLabel: String {
        switch self {
        case .domain: return "도메인"
        case .app: return "앱"
        case .titleKeyword: return "제목 키워드"
        case .urlPattern: return "URL 패턴"
        }
    }
}

public struct ClassificationRule: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let ruleType: RuleType
    public let pattern: String
    public let category: ActivityCategory
    public let priority: Int
    public let isBuiltin: Bool
    public let isEnabled: Bool

    public init(
        id: String,
        name: String,
        ruleType: RuleType,
        pattern: String,
        category: ActivityCategory,
        priority: Int,
        isBuiltin: Bool,
        isEnabled: Bool
    ) {
        self.id = id
        self.name = name
        self.ruleType = ruleType
        self.pattern = pattern
        self.category = category
        self.priority = priority
        self.isBuiltin = isBuiltin
        self.isEnabled = isEnabled
    }
}

public struct ActivitySessionRecord: Equatable {
    public let id: String
    public let startedAt: Date
    public let endedAt: Date
    public let durationSeconds: Int
    public let appName: String
    public let processName: String
    public let windowTitle: String
    public let domain: String?
    public let url: String?
    public let isIdle: Bool

    public init(
        id: String,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        appName: String,
        processName: String,
        windowTitle: String,
        domain: String?,
        url: String?,
        isIdle: Bool
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.appName = appName
        self.processName = processName
        self.windowTitle = windowTitle
        self.domain = domain
        self.url = url
        self.isIdle = isIdle
    }
}

public struct DashboardReportData: Equatable {
    public let summary: DashboardSummary
    public let usageItems: [UsageItem]
    public let timelineSessions: [TimelineSession]

    public init(
        summary: DashboardSummary,
        usageItems: [UsageItem],
        timelineSessions: [TimelineSession]
    ) {
        self.summary = summary
        self.usageItems = usageItems
        self.timelineSessions = timelineSessions
    }
}

public struct ActivitySample: Equatable {
    public let observedAt: Date
    public let appName: String
    public let processName: String
    public let windowTitle: String
    public let domain: String?
    public let isIdle: Bool

    public init(
        observedAt: Date,
        appName: String,
        processName: String,
        windowTitle: String,
        domain: String? = nil,
        isIdle: Bool = false
    ) {
        self.observedAt = observedAt
        self.appName = appName
        self.processName = processName
        self.windowTitle = windowTitle
        self.domain = domain
        self.isIdle = isIdle
    }
}

public struct WindowObservationRecord: Equatable {
    public let observedAt: Date
    public let appName: String
    public let processName: String
    public let pid: Int32?
    public let bundleIdentifier: String?
    public let windowTitle: String?
    public let isVisible: Bool
    public let isFrontmost: Bool
    public let isPrimary: Bool

    public init(
        observedAt: Date,
        appName: String,
        processName: String,
        pid: Int32?,
        bundleIdentifier: String?,
        windowTitle: String?,
        isVisible: Bool,
        isFrontmost: Bool,
        isPrimary: Bool
    ) {
        self.observedAt = observedAt
        self.appName = appName
        self.processName = processName
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.isVisible = isVisible
        self.isFrontmost = isFrontmost
        self.isPrimary = isPrimary
    }
}

public struct ActivitySnapshot: Equatable {
    public let primarySample: ActivitySample
    public let visibleWindows: [WindowObservationRecord]

    public init(primarySample: ActivitySample, visibleWindows: [WindowObservationRecord]) {
        self.primarySample = primarySample
        self.visibleWindows = visibleWindows
    }
}

public struct BrowserEventRecord: Equatable {
    public let id: String
    public let occurredAt: Date
    public let domain: String
    public let url: String?
    public let title: String

    public init(
        id: String,
        occurredAt: Date,
        domain: String,
        url: String?,
        title: String
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.domain = domain
        self.url = url
        self.title = title
    }
}

public struct BrowserEventDraft: Equatable, Decodable {
    public let domain: String
    public let url: String?
    public let title: String

    public init(domain: String, url: String?, title: String) {
        self.domain = domain
        self.url = url
        self.title = title
    }
}

public struct UncategorizedItem: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let ruleType: RuleType
    public let pattern: String
    public let durationSeconds: Int
    public let sessionCount: Int

    public init(
        id: String,
        name: String,
        ruleType: RuleType,
        pattern: String,
        durationSeconds: Int,
        sessionCount: Int
    ) {
        self.id = id
        self.name = name
        self.ruleType = ruleType
        self.pattern = pattern
        self.durationSeconds = durationSeconds
        self.sessionCount = sessionCount
    }
}
