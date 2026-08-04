import Foundation

public final class ProcessSampler: @unchecked Sendable {
    private let commandRunner: () throws -> String
    private let bundleIdentifierResolver: (String) -> String?
    private let cacheLock = NSLock()
    private var bundleIdentifierCache: [String: CachedBundleIdentifier] = [:]

    public convenience init() {
        self.init(
            commandRunner: {
                try ProcessCommand.run("/bin/ps", arguments: ["-axo", "pid=,pcpu=,rss=,comm="])
            },
            bundleIdentifierResolver: Self.bundleIdentifierFromOwningApplication
        )
    }

    convenience init(commandRunner: @escaping () throws -> String) {
        self.init(
            commandRunner: commandRunner,
            bundleIdentifierResolver: Self.bundleIdentifierFromOwningApplication
        )
    }

    init(
        commandRunner: @escaping () throws -> String,
        bundleIdentifierResolver: @escaping (String) -> String?
    ) {
        self.commandRunner = commandRunner
        self.bundleIdentifierResolver = bundleIdentifierResolver
    }

    public func sample(limit: Int? = nil) throws -> [ProcessMetric] {
        let output = try commandRunner()
        let processes = output
            .split(whereSeparator: \.isNewline)
            .compactMap(parseLine)

        let sorted = ProcessSorting.filtered(processes, searchText: "", sortKey: .cpu)
        if let limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    private func parseLine(_ line: Substring) -> ProcessMetric? {
        let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count == 4,
              let pid = Int32(parts[0]),
              let cpu = Double(parts[1]),
              let rssKB = UInt64(parts[2])
        else {
            return nil
        }

        let path = String(parts[3])
        let name = URL(fileURLWithPath: path).lastPathComponent.isEmpty
            ? path
            : URL(fileURLWithPath: path).lastPathComponent
        return ProcessMetric(
            pid: pid,
            name: name,
            cpuPercent: cpu,
            memoryBytes: rssKB * 1_024,
            path: path,
            bundleIdentifier: bundleIdentifier(for: path)
        )
    }

    private func bundleIdentifier(for path: String) -> String? {
        cacheLock.lock()
        if let cached = bundleIdentifierCache[path] {
            cacheLock.unlock()
            return cached.value
        }
        cacheLock.unlock()

        let resolved = bundleIdentifierResolver(path)

        cacheLock.lock()
        bundleIdentifierCache[path] = resolved.map(CachedBundleIdentifier.resolved) ?? .unavailable
        cacheLock.unlock()

        return resolved
    }

    private static func bundleIdentifierFromOwningApplication(path: String) -> String? {
        guard let appURL = owningApplicationURL(from: path) else { return nil }
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any],
              let bundleIdentifier = dictionary["CFBundleIdentifier"] as? String,
              !bundleIdentifier.isEmpty
        else {
            return nil
        }
        return bundleIdentifier
    }

    private static func owningApplicationURL(from path: String) -> URL? {
        let url = URL(fileURLWithPath: path)
        var collectedComponents: [String] = []
        for component in url.pathComponents {
            collectedComponents.append(component)
            if component.hasSuffix(".app") {
                return URL(fileURLWithPath: NSString.path(withComponents: collectedComponents))
            }
        }
        return nil
    }
}

private enum CachedBundleIdentifier {
    case resolved(String)
    case unavailable

    var value: String? {
        switch self {
        case .resolved(let value):
            value
        case .unavailable:
            nil
        }
    }
}
