import Foundation

public enum StartupItemScope: String, CaseIterable, Sendable {
    case userLaunchAgent
    case globalLaunchAgent
    case globalLaunchDaemon

    public var title: String {
        switch self {
        case .userLaunchAgent: "User LaunchAgent"
        case .globalLaunchAgent: "Global LaunchAgent"
        case .globalLaunchDaemon: "LaunchDaemon"
        }
    }
}

public enum StartupItemState: String, Sendable {
    case enabled
    case disabled

    public var title: String {
        switch self {
        case .enabled: "Enabled"
        case .disabled: "Disabled"
        }
    }
}

public struct StartupItem: Identifiable, Equatable, Sendable {
    public var id: String { plistURL.path }

    public let label: String
    public let plistURL: URL
    public let scope: StartupItemScope
    public let state: StartupItemState
    public let program: String?
    public let programArguments: [String]
    public let runAtLoad: Bool
    public let keepAliveSummary: String?
    public let startInterval: Int?
    public let startCalendarSummary: String?
    public let disabledFlag: Bool
    public let disabledByRename: Bool
    public let targetURL: URL?
    public let targetExists: Bool
    public let ownerName: String
    public let ownerEvidence: String

    public init(
        label: String,
        plistURL: URL,
        scope: StartupItemScope,
        state: StartupItemState,
        program: String?,
        programArguments: [String],
        runAtLoad: Bool,
        keepAliveSummary: String?,
        startInterval: Int?,
        startCalendarSummary: String?,
        disabledFlag: Bool,
        disabledByRename: Bool,
        targetURL: URL?,
        targetExists: Bool,
        ownerName: String,
        ownerEvidence: String
    ) {
        self.label = label
        self.plistURL = plistURL
        self.scope = scope
        self.state = state
        self.program = program
        self.programArguments = programArguments
        self.runAtLoad = runAtLoad
        self.keepAliveSummary = keepAliveSummary
        self.startInterval = startInterval
        self.startCalendarSummary = startCalendarSummary
        self.disabledFlag = disabledFlag
        self.disabledByRename = disabledByRename
        self.targetURL = targetURL
        self.targetExists = targetExists
        self.ownerName = ownerName
        self.ownerEvidence = ownerEvidence
    }

    public var isEditable: Bool {
        scope == .userLaunchAgent
    }

    public var isReadOnly: Bool {
        !isEditable
    }

    public var hasMissingTarget: Bool {
        targetURL != nil && !targetExists
    }
}
