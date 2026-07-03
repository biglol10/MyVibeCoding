import Foundation

public struct StartupItemScanner: Sendable {
    private let userLaunchAgentsURL: URL
    private let globalLaunchAgentsURL: URL
    private let globalLaunchDaemonsURL: URL

    public init(
        userLaunchAgentsURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents", isDirectory: true),
        globalLaunchAgentsURL: URL = URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true),
        globalLaunchDaemonsURL: URL = URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true)
    ) {
        self.userLaunchAgentsURL = userLaunchAgentsURL
        self.globalLaunchAgentsURL = globalLaunchAgentsURL
        self.globalLaunchDaemonsURL = globalLaunchDaemonsURL
    }

    public func scan() async throws -> [StartupItem] {
        let roots: [(URL, StartupItemScope)] = [
            (userLaunchAgentsURL, .userLaunchAgent),
            (globalLaunchAgentsURL, .globalLaunchAgent),
            (globalLaunchDaemonsURL, .globalLaunchDaemon)
        ]

        var items: [StartupItem] = []
        for (root, scope) in roots {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in urls where Self.isLaunchPlist(url) {
                guard let item = try? parseItem(at: url, scope: scope) else {
                    continue
                }
                items.append(item)
            }
        }

        return items.sorted { lhs, rhs in
            let lhsScopeIndex = StartupItemScope.allCases.firstIndex(of: lhs.scope) ?? .max
            let rhsScopeIndex = StartupItemScope.allCases.firstIndex(of: rhs.scope) ?? .max
            if lhsScopeIndex == rhsScopeIndex {
                return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
            }
            return lhsScopeIndex < rhsScopeIndex
        }
    }

    private static func isLaunchPlist(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasSuffix(".plist") || name.hasSuffix(".plist.mymacclean-disabled")
    }

    private func parseItem(at url: URL, scope: StartupItemScope) throws -> StartupItem {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let label = (plist["Label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? fallbackLabel(for: url)
        let program = plist["Program"] as? String
        let programArguments = plist["ProgramArguments"] as? [String] ?? []
        let disabledFlag = plist["Disabled"] as? Bool ?? false
        let disabledByRename = url.lastPathComponent.hasSuffix(".plist.mymacclean-disabled")
        let state: StartupItemState = (disabledFlag || disabledByRename) ? .disabled : .enabled
        let targetURL = Self.targetURL(program: program, arguments: programArguments)
        let targetExists = targetURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let owner = Self.owner(program: program, arguments: programArguments, label: label)

        return StartupItem(
            label: label,
            plistURL: url,
            scope: scope,
            state: state,
            program: program,
            programArguments: programArguments,
            runAtLoad: plist["RunAtLoad"] as? Bool ?? false,
            keepAliveSummary: Self.keepAliveSummary(from: plist["KeepAlive"]),
            startInterval: plist["StartInterval"] as? Int,
            startCalendarSummary: Self.startCalendarSummary(from: plist["StartCalendarInterval"]),
            disabledFlag: disabledFlag,
            disabledByRename: disabledByRename,
            targetURL: targetURL,
            targetExists: targetExists,
            ownerName: owner.name,
            ownerEvidence: owner.evidence
        )
    }

    private func fallbackLabel(for url: URL) -> String {
        var name = url.lastPathComponent
        if name.hasSuffix(".mymacclean-disabled") {
            name = String(name.dropLast(".mymacclean-disabled".count))
        }
        if name.hasSuffix(".plist") {
            name = String(name.dropLast(".plist".count))
        }
        return name
    }

    private static func targetURL(program: String?, arguments: [String]) -> URL? {
        let target = program ?? arguments.first
        guard let target, target.hasPrefix("/") else {
            return nil
        }
        return URL(fileURLWithPath: target)
    }

    private static func owner(program: String?, arguments: [String], label: String) -> (name: String, evidence: String) {
        let paths = ([program] + arguments).compactMap { $0 }
        if let appComponent = paths
            .flatMap({ URL(fileURLWithPath: $0).pathComponents })
            .first(where: { $0.hasSuffix(".app") }) {
            return (
                name: String(appComponent.dropLast(".app".count)),
                evidence: "Application path: \(appComponent)"
            )
        }

        if let program, !program.isEmpty {
            return (
                name: URL(fileURLWithPath: program).deletingPathExtension().lastPathComponent,
                evidence: "Program path"
            )
        }

        let parts = label.split(separator: ".").map(String.init)
        if let last = parts.last, !last.isEmpty {
            return (name: last, evidence: "Launch label")
        }
        return (name: label, evidence: "Launch label")
    }

    private static func keepAliveSummary(from value: Any?) -> String? {
        switch value {
        case let bool as Bool:
            return bool ? "true" : "false"
        case let dictionary as [String: Any]:
            let keys = dictionary.keys.sorted()
            return keys.isEmpty ? "configured" : keys.joined(separator: ", ")
        case .some:
            return "configured"
        case .none:
            return nil
        }
    }

    private static func startCalendarSummary(from value: Any?) -> String? {
        switch value {
        case let dictionary as [String: Any]:
            return calendarDictionarySummary(dictionary)
        case let array as [[String: Any]]:
            return array.map(calendarDictionarySummary).joined(separator: "; ")
        case .some:
            return "configured"
        case .none:
            return nil
        }
    }

    private static func calendarDictionarySummary(_ dictionary: [String: Any]) -> String {
        let order = ["Month", "Day", "Weekday", "Hour", "Minute"]
        let parts = order.compactMap { key -> String? in
            guard let value = dictionary[key] else { return nil }
            return "\(key)=\(value)"
        }
        return parts.isEmpty ? "configured" : parts.joined(separator: " ")
    }
}
