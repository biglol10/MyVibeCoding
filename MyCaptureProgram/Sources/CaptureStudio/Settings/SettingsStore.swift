import Foundation
import SwiftUI

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public private(set) var settings: AppSettings
    @Published public private(set) var persistenceErrorMessage: String?

    private let defaults: UserDefaults
    private let storageKey = "CaptureStudio.AppSettings.v1"
    private let encodeSettings: (AppSettings) throws -> Data

    public init(
        defaults: UserDefaults = .standard,
        encodeSettings: @escaping (AppSettings) throws -> Data = { try JSONEncoder().encode($0) }
    ) {
        self.defaults = defaults
        self.encodeSettings = encodeSettings

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .defaults
        }
    }

    public func update(_ mutate: (inout AppSettings) -> Void) {
        var next = settings
        mutate(&next)
        settings = next
        persist(next)
    }

    public func reset() {
        settings = .defaults
        persist(.defaults)
    }

    private func persist(_ settings: AppSettings) {
        do {
            let data = try encodeSettings(settings)
            defaults.set(data, forKey: storageKey)
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
    }
}
