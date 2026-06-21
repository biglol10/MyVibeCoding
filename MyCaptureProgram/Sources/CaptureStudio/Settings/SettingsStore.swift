import Foundation
import SwiftUI

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public private(set) var settings: AppSettings

    private let defaults: UserDefaults
    private let storageKey = "CaptureStudio.AppSettings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

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
        let data = try? JSONEncoder().encode(settings)
        defaults.set(data, forKey: storageKey)
    }
}
