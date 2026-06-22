import Foundation

public enum MetricKind: String, CaseIterable, Identifiable, Equatable, Sendable {
    case cpu
    case memory
    case disk
    case network
    case battery
    case processes

    public var id: Self { self }

    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "RAM"
        case .disk: "Disk"
        case .network: "Network"
        case .battery: "Battery"
        case .processes: "Processes"
        }
    }

    public var systemImage: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .battery: "battery.75"
        case .processes: "list.bullet.rectangle"
        }
    }
}

public enum HealthState: Equatable, Sendable {
    case normal
    case warning
    case critical
    case unavailable
}

public struct MetricSummary: Equatable, Identifiable, Sendable {
    public let kind: MetricKind
    public let title: String
    public let valueText: String
    public let detailText: String?
    public let health: HealthState
    public let updatedAt: Date

    public var id: MetricKind { kind }

    public init(
        kind: MetricKind,
        title: String,
        valueText: String,
        detailText: String?,
        health: HealthState,
        updatedAt: Date
    ) {
        self.kind = kind
        self.title = title
        self.valueText = valueText
        self.detailText = detailText
        self.health = health
        self.updatedAt = updatedAt
    }
}

public struct ProcessMetric: Equatable, Identifiable, Sendable {
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let path: String?
    public let bundleIdentifier: String?

    public var id: Int32 { pid }

    public init(
        pid: Int32,
        name: String,
        cpuPercent: Double,
        memoryBytes: UInt64,
        path: String?,
        bundleIdentifier: String?
    ) {
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.path = path
        self.bundleIdentifier = bundleIdentifier
    }
}

public enum MemoryPressure: Equatable, Sendable {
    case normal
    case warning
    case critical
    case unavailable
}

public struct CPUSnapshot: Equatable, Sendable {
    public let totalUsagePercent: Double
    public let userPercent: Double
    public let systemPercent: Double
    public let idlePercent: Double
    public let sampledAt: Date

    public init(
        totalUsagePercent: Double,
        userPercent: Double,
        systemPercent: Double,
        idlePercent: Double,
        sampledAt: Date = Date()
    ) {
        self.totalUsagePercent = totalUsagePercent
        self.userPercent = userPercent
        self.systemPercent = systemPercent
        self.idlePercent = idlePercent
        self.sampledAt = sampledAt
    }
}

public struct MemorySnapshot: Equatable, Sendable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let freeBytes: UInt64
    public let compressedBytes: UInt64?
    public let cachedBytes: UInt64?
    public let swapUsedBytes: UInt64?
    public let pressure: MemoryPressure
    public let sampledAt: Date

    public init(
        totalBytes: UInt64,
        usedBytes: UInt64,
        freeBytes: UInt64,
        compressedBytes: UInt64?,
        cachedBytes: UInt64?,
        swapUsedBytes: UInt64?,
        pressure: MemoryPressure,
        sampledAt: Date = Date()
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
        self.compressedBytes = compressedBytes
        self.cachedBytes = cachedBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressure = pressure
        self.sampledAt = sampledAt
    }

    public var usageRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}

public struct DiskSnapshot: Equatable, Sendable {
    public let volumeName: String
    public let mountPoint: String
    public let totalBytes: UInt64
    public let freeBytes: UInt64
    public let readBytesPerSecond: UInt64?
    public let writeBytesPerSecond: UInt64?
    public let sampledAt: Date

    public init(
        volumeName: String,
        mountPoint: String,
        totalBytes: UInt64,
        freeBytes: UInt64,
        readBytesPerSecond: UInt64?,
        writeBytesPerSecond: UInt64?,
        sampledAt: Date = Date()
    ) {
        self.volumeName = volumeName
        self.mountPoint = mountPoint
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.readBytesPerSecond = readBytesPerSecond
        self.writeBytesPerSecond = writeBytesPerSecond
        self.sampledAt = sampledAt
    }

    public var freeRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(freeBytes) / Double(totalBytes)
    }
}

public struct NetworkSnapshot: Equatable, Sendable {
    public let interfaceName: String?
    public let downloadBytesPerSecond: UInt64
    public let uploadBytesPerSecond: UInt64
    public let receivedBytes: UInt64
    public let sentBytes: UInt64
    public let isConnected: Bool
    public let sampledAt: Date

    public init(
        interfaceName: String?,
        downloadBytesPerSecond: UInt64,
        uploadBytesPerSecond: UInt64,
        receivedBytes: UInt64,
        sentBytes: UInt64,
        isConnected: Bool,
        sampledAt: Date = Date()
    ) {
        self.interfaceName = interfaceName
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
        self.isConnected = isConnected
        self.sampledAt = sampledAt
    }
}

public struct BatterySnapshot: Equatable, Sendable {
    public let isPresent: Bool
    public let percentage: Double?
    public let isCharging: Bool?
    public let powerSource: String
    public let timeRemainingMinutes: Int?
    public let cycleCount: Int?
    public let serviceRecommended: Bool
    public let sampledAt: Date

    public init(
        isPresent: Bool,
        percentage: Double?,
        isCharging: Bool?,
        powerSource: String,
        timeRemainingMinutes: Int?,
        cycleCount: Int?,
        serviceRecommended: Bool,
        sampledAt: Date = Date()
    ) {
        self.isPresent = isPresent
        self.percentage = percentage
        self.isCharging = isCharging
        self.powerSource = powerSource
        self.timeRemainingMinutes = timeRemainingMinutes
        self.cycleCount = cycleCount
        self.serviceRecommended = serviceRecommended
        self.sampledAt = sampledAt
    }
}

public enum ProcessSortKey: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory
    case name
    case pid

    public var id: Self { self }

    public var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .name: "Name"
        case .pid: "PID"
        }
    }
}

public enum RefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case oneSecond = 1
    case twoSeconds = 2
    case fiveSeconds = 5
    case tenSeconds = 10

    public var id: Int { rawValue }
    public var seconds: TimeInterval { TimeInterval(rawValue) }
    public var title: String { "\(rawValue)s" }
}
