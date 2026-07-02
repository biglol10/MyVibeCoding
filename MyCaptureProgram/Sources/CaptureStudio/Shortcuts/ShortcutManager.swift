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
            let supportedActions = Set(ShortcutDefinition.customizableActions)
            let filteredDecoded = decoded.filter { supportedActions.contains($0.key) }
            self.bindings = ShortcutDefinition.defaultBindings.merging(filteredDecoded) { _, custom in custom }
        } else {
            self.bindings = ShortcutDefinition.defaultBindings
        }
    }

    public func setBinding(_ binding: ShortcutBinding, for action: ShortcutAction) throws {
        if let duplicate = bindings.first(where: { $0.key != action && $0.value == binding })?.key {
            throw ShortcutError.duplicateBinding(existingAction: duplicate)
        }

        var updatedBindings = bindings
        updatedBindings[action] = binding
        bindings = updatedBindings
        persist()
    }

    public func resetToDefault(_ action: ShortcutAction) {
        var updatedBindings = bindings
        updatedBindings[action] = ShortcutDefinition.defaultBinding(for: action)
        bindings = updatedBindings
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

    public func clearRegistrationFailure(for action: ShortcutAction) {
        registrationFailures[action] = nil
    }

    public func clearAllRegistrationFailures() {
        registrationFailures = [:]
    }

    private func persist() {
        let data = try? JSONEncoder().encode(bindings)
        defaults.set(data, forKey: storageKey)
    }
}
