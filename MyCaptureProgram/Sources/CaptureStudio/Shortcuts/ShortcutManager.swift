import Foundation
import SwiftUI

@MainActor
public final class ShortcutManager: ObservableObject {
    public enum ShortcutError: Error, Equatable {
        case duplicateBinding(existingAction: ShortcutAction)
    }

    @Published public private(set) var bindings: [ShortcutAction: ShortcutBinding]
    @Published public private(set) var registrationFailures: [ShortcutAction: String]

    private let defaults: UserDefaults
    private let storageKey = "CaptureStudio.ShortcutBindings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.registrationFailures = [:]

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ShortcutAction: ShortcutBinding].self, from: data) {
            self.bindings = ShortcutDefinition.defaultBindings.merging(decoded) { _, custom in custom }
        } else {
            self.bindings = ShortcutDefinition.defaultBindings
        }
    }

    public func setBinding(_ binding: ShortcutBinding, for action: ShortcutAction) throws {
        if let duplicate = bindings.first(where: { $0.key != action && $0.value == binding })?.key {
            throw ShortcutError.duplicateBinding(existingAction: duplicate)
        }

        bindings[action] = binding
        persist()
    }

    public func resetToDefault(_ action: ShortcutAction) {
        bindings[action] = ShortcutDefinition.defaultBinding(for: action)
        persist()
    }

    public func resetAllToDefaults() {
        bindings = ShortcutDefinition.defaultBindings
        registrationFailures = [:]
        persist()
    }

    public func markRegistrationFailed(for action: ShortcutAction, reason: String) {
        registrationFailures[action] = reason
    }

    private func persist() {
        let data = try? JSONEncoder().encode(bindings)
        defaults.set(data, forKey: storageKey)
    }
}
