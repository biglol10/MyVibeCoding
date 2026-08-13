import Foundation

public struct ExplorerSettings: Codable, Equatable, Sendable {
    public var paneMode: ExplorerPaneMode
    public var isInspectorVisible: Bool
    public var showHiddenFiles: Bool
    public var defaultSort: EntrySortDescriptor
    public var previewMode: FilePreviewMode
    public var previewByteLimit: FilePreviewByteLimit
    public var restorePreviousSession: Bool

    public init(
        paneMode: ExplorerPaneMode = .single,
        isInspectorVisible: Bool = true,
        showHiddenFiles: Bool = false,
        defaultSort: EntrySortDescriptor = EntrySortDescriptor(),
        previewMode: FilePreviewMode = .smart,
        previewByteLimit: FilePreviewByteLimit = .balanced,
        restorePreviousSession: Bool = true
    ) {
        self.paneMode = paneMode
        self.isInspectorVisible = isInspectorVisible
        self.showHiddenFiles = showHiddenFiles
        self.defaultSort = defaultSort
        self.previewMode = previewMode
        self.previewByteLimit = previewByteLimit
        self.restorePreviousSession = restorePreviousSession
    }

    private enum CodingKeys: String, CodingKey {
        case paneMode
        case isInspectorVisible
        case showHiddenFiles
        case defaultSort
        case previewMode
        case previewByteLimit
        case restorePreviousSession
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.paneMode = try container.decodeIfPresent(ExplorerPaneMode.self, forKey: .paneMode) ?? .single
        self.isInspectorVisible = try container.decodeIfPresent(Bool.self, forKey: .isInspectorVisible) ?? true
        self.showHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .showHiddenFiles) ?? false
        self.defaultSort = try container.decodeIfPresent(EntrySortDescriptor.self, forKey: .defaultSort) ?? EntrySortDescriptor()
        self.previewMode = try container.decodeIfPresent(FilePreviewMode.self, forKey: .previewMode) ?? .smart
        self.previewByteLimit = try container.decodeIfPresent(FilePreviewByteLimit.self, forKey: .previewByteLimit) ?? .balanced
        self.restorePreviousSession = try container.decodeIfPresent(Bool.self, forKey: .restorePreviousSession) ?? true
    }
}

public protocol ExplorerSettingsStoring: AnyObject {
    func load() throws -> ExplorerSettings
    func save(_ settings: ExplorerSettings) throws
    func reset() throws
}

public extension ExplorerSettingsStoring {
    func reset() throws {}
}

public final class UserDefaultsExplorerSettingsStore: ExplorerSettingsStoring {
    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "MyMacFinder.ExplorerSettings"
    ) {
        self.defaults = defaults
        self.key = key
    }

    public func load() throws -> ExplorerSettings {
        guard let data = defaults.data(forKey: key) else {
            return ExplorerSettings()
        }

        return try JSONDecoder().decode(ExplorerSettings.self, from: data)
    }

    public func save(_ settings: ExplorerSettings) throws {
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: key)
    }

    public func reset() throws {
        defaults.removeObject(forKey: key)
    }
}
