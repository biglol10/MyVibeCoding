import Foundation

public struct ExplorerSettings: Codable, Equatable, Sendable {
    public var paneMode: ExplorerPaneMode
    public var isInspectorVisible: Bool
    public var showHiddenFiles: Bool
    public var defaultSort: EntrySortDescriptor

    public init(
        paneMode: ExplorerPaneMode = .single,
        isInspectorVisible: Bool = true,
        showHiddenFiles: Bool = false,
        defaultSort: EntrySortDescriptor = EntrySortDescriptor()
    ) {
        self.paneMode = paneMode
        self.isInspectorVisible = isInspectorVisible
        self.showHiddenFiles = showHiddenFiles
        self.defaultSort = defaultSort
    }

    private enum CodingKeys: String, CodingKey {
        case paneMode
        case isInspectorVisible
        case showHiddenFiles
        case defaultSort
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.paneMode = try container.decodeIfPresent(ExplorerPaneMode.self, forKey: .paneMode) ?? .single
        self.isInspectorVisible = try container.decodeIfPresent(Bool.self, forKey: .isInspectorVisible) ?? true
        self.showHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .showHiddenFiles) ?? false
        self.defaultSort = try container.decodeIfPresent(EntrySortDescriptor.self, forKey: .defaultSort) ?? EntrySortDescriptor()
    }
}

public protocol ExplorerSettingsStoring: AnyObject {
    func load() -> ExplorerSettings
    func save(_ settings: ExplorerSettings)
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

    public func load() -> ExplorerSettings {
        guard let data = defaults.data(forKey: key) else {
            return ExplorerSettings()
        }

        do {
            return try JSONDecoder().decode(ExplorerSettings.self, from: data)
        } catch {
            return ExplorerSettings()
        }
    }

    public func save(_ settings: ExplorerSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}
