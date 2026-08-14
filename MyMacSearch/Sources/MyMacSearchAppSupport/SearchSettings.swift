import Foundation
import MyMacSearchCore

public struct SearchScopeSetting: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var rootPath: String
    public var volumeType: IndexedVolumeType
    public var isEnabled: Bool
    public var expectedVolumeUUID: String?

    public init(
        id: String = UUID().uuidString,
        rootPath: String,
        volumeType: IndexedVolumeType = .internalLocal,
        isEnabled: Bool = true,
        expectedVolumeUUID: String? = nil
    ) {
        self.id = id
        self.rootPath = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        self.volumeType = volumeType
        self.isEnabled = isEnabled
        self.expectedVolumeUUID = expectedVolumeUUID
    }

    public var indexScope: IndexScope {
        IndexScope(
            id: id,
            rootPath: rootPath,
            volumeType: volumeType,
            isEnabled: isEnabled
        )
    }
}

public struct GlobalShortcutSetting: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32 = 49, modifiers: UInt32 = 1 << 11) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public struct SearchSettings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var scopes: [SearchScopeSetting]
    public var excludedPaths: [String]
    public var includeHidden: Bool
    public var externalVolumesEnabled: Bool
    public var networkVolumesEnabled: Bool
    public var onboardingConfirmed: Bool
    public var globalShortcut: GlobalShortcutSetting
    public var preferredSort: SearchSort?

    public init(
        schemaVersion: Int = currentSchemaVersion,
        scopes: [SearchScopeSetting],
        excludedPaths: [String] = [],
        includeHidden: Bool = false,
        externalVolumesEnabled: Bool = false,
        networkVolumesEnabled: Bool = false,
        onboardingConfirmed: Bool = false,
        globalShortcut: GlobalShortcutSetting = GlobalShortcutSetting(),
        preferredSort: SearchSort? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.scopes = scopes
        self.excludedPaths = excludedPaths
        self.includeHidden = includeHidden
        self.externalVolumesEnabled = externalVolumesEnabled
        self.networkVolumesEnabled = networkVolumesEnabled
        self.onboardingConfirmed = onboardingConfirmed
        self.globalShortcut = globalShortcut
        self.preferredSort = preferredSort
    }

    public static func recommended(
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> SearchSettings {
        let relativePaths = [
            "Desktop",
            "Documents",
            "Downloads",
            "Developer/Projects",
            "Projects"
        ]
        let scopes = relativePaths.compactMap { relativePath -> SearchScopeSetting? in
            let url = homeURL.appendingPathComponent(relativePath, isDirectory: true)
                .standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }
            return SearchScopeSetting(rootPath: url.path)
        }
        return SearchSettings(scopes: scopes)
    }
}

public enum SearchSettingsStoreError: Error, LocalizedError, Equatable, Sendable {
    case noSettings
    case corruptSettings
    case unsupportedSchema(Int)

    public var errorDescription: String? {
        switch self {
        case .noSettings:
            return "No saved MyMacSearch settings were found."
        case .corruptSettings:
            return "Saved MyMacSearch settings could not be read."
        case .unsupportedSchema(let version):
            return "Unsupported MyMacSearch settings version: \(version)."
        }
    }
}

public final class SearchSettingsStore {
    public let settingsURL: URL
    public let lastGoodURL: URL
    public private(set) var didRecoverLastGood = false

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directoryURL: URL, fileManager: FileManager = .default) {
        settingsURL = directoryURL.appendingPathComponent("Settings.json")
        lastGoodURL = directoryURL.appendingPathComponent("Settings.last-good.json")
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    public func load() throws -> SearchSettings {
        didRecoverLastGood = false
        if let settings = try? decodedSettings(at: settingsURL) {
            return settings
        }
        if let settings = try? decodedSettings(at: lastGoodURL) {
            didRecoverLastGood = true
            return settings
        }
        if !fileManager.fileExists(atPath: settingsURL.path),
           !fileManager.fileExists(atPath: lastGoodURL.path) {
            throw SearchSettingsStoreError.noSettings
        }
        throw SearchSettingsStoreError.corruptSettings
    }

    public func save(_ settings: SearchSettings) throws {
        guard settings.schemaVersion == SearchSettings.currentSchemaVersion else {
            throw SearchSettingsStoreError.unsupportedSchema(settings.schemaVersion)
        }
        try fileManager.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoded = try encoder.encode(settings)
        _ = try decoder.decode(SearchSettings.self, from: encoded)

        if let previous = try? Data(contentsOf: settingsURL),
           (try? validated(previous)) != nil {
            try previous.write(to: lastGoodURL, options: .atomic)
        }
        try encoded.write(to: settingsURL, options: .atomic)
        if !fileManager.fileExists(atPath: lastGoodURL.path) {
            try encoded.write(to: lastGoodURL, options: .atomic)
        }
        didRecoverLastGood = false
    }

    private func decodedSettings(at url: URL) throws -> SearchSettings {
        try validated(Data(contentsOf: url))
    }

    private func validated(_ data: Data) throws -> SearchSettings {
        let settings = try decoder.decode(SearchSettings.self, from: data)
        guard settings.schemaVersion == SearchSettings.currentSchemaVersion else {
            throw SearchSettingsStoreError.unsupportedSchema(settings.schemaVersion)
        }
        return settings
    }
}
