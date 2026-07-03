import Foundation

public enum DeveloperCacheTool: String, CaseIterable, Codable, Equatable, Sendable {
    case xcodeDerivedData
    case xcodeArchives
    case xcodeDeviceSupport
    case swiftPackageManager
    case npm
    case yarn
    case pnpm
    case cocoaPods
    case gradle
    case docker

    public var title: String {
        switch self {
        case .xcodeDerivedData: "Xcode DerivedData"
        case .xcodeArchives: "Xcode Archives"
        case .xcodeDeviceSupport: "Xcode DeviceSupport"
        case .swiftPackageManager: "SwiftPM Cache"
        case .npm: "npm Cache"
        case .yarn: "Yarn Cache"
        case .pnpm: "pnpm Store"
        case .cocoaPods: "CocoaPods Cache"
        case .gradle: "Gradle Cache"
        case .docker: "Docker Storage"
        }
    }

    public var groupTitle: String {
        switch self {
        case .xcodeDerivedData, .xcodeArchives, .xcodeDeviceSupport:
            "Xcode"
        case .swiftPackageManager:
            "Swift"
        case .npm, .yarn, .pnpm:
            "Node"
        case .cocoaPods:
            "CocoaPods"
        case .gradle:
            "Gradle"
        case .docker:
            "Docker"
        }
    }
}

public enum DeveloperCacheSafety: String, CaseIterable, Codable, Equatable, Sendable {
    case safe
    case review
    case readOnly

    public var title: String {
        switch self {
        case .safe: "Safe"
        case .review: "Review"
        case .readOnly: "Read-only"
        }
    }

    public var isDeletable: Bool {
        self != .readOnly
    }

    public var defaultSelected: Bool {
        self == .safe
    }
}

public enum DeveloperCacheSort: String, CaseIterable, Identifiable, Sendable {
    case tool
    case sizeDescending
    case safety

    public var id: Self { self }

    public var title: String {
        switch self {
        case .tool: "Tool"
        case .sizeDescending: "Size"
        case .safety: "Safety"
        }
    }
}

public struct DeveloperCacheCandidate: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let tool: DeveloperCacheTool
    public let url: URL
    public let size: Int64
    public let safety: DeveloperCacheSafety
    public let explanation: String

    public init(
        id: UUID = UUID(),
        tool: DeveloperCacheTool,
        url: URL,
        size: Int64,
        safety: DeveloperCacheSafety,
        explanation: String
    ) {
        self.id = id
        self.tool = tool
        self.url = url
        self.size = size
        self.safety = safety
        self.explanation = explanation
    }

    public var defaultSelected: Bool {
        safety.defaultSelected
    }

    public var isDeletable: Bool {
        safety.isDeletable
    }
}
