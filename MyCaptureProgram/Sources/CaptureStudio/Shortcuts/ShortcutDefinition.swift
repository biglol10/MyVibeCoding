import Foundation
import SwiftUI

public enum ShortcutAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case newScreenshot
    case newRecording
    case textExtraction
    case colorPicker
    case lastCapture
    case openSettings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .newScreenshot:
            return "New Screenshot"
        case .newRecording:
            return "New Recording"
        case .textExtraction:
            return "Text Extraction"
        case .colorPicker:
            return "Color Picker"
        case .lastCapture:
            return "Last Capture"
        case .openSettings:
            return "Open Settings"
        }
    }
}

public enum ShortcutModifier: String, CaseIterable, Codable, Comparable, Sendable {
    case command
    case shift
    case option
    case control

    public static func < (lhs: ShortcutModifier, rhs: ShortcutModifier) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .control:
            return 0
        case .option:
            return 1
        case .shift:
            return 2
        case .command:
            return 3
        }
    }
}

public struct ShortcutBinding: Codable, Equatable, Hashable, Sendable {
    public var key: String
    public var modifiers: [ShortcutModifier]

    public init(key: String, modifiers: [ShortcutModifier]) {
        self.key = key.uppercased()
        self.modifiers = modifiers.sorted()
    }

    public var displayValue: String {
        let modifierText = modifiers.map(\.symbol).joined()
        return "\(modifierText)\(key)"
    }

    public var keyEquivalent: KeyEquivalent {
        KeyEquivalent(key.first ?? " ")
    }

    public var eventModifiers: EventModifiers {
        var eventModifiers: EventModifiers = []

        for modifier in modifiers {
            eventModifiers.insert(modifier.eventModifier)
        }

        return eventModifiers
    }
}

public extension ShortcutModifier {
    var symbol: String {
        switch self {
        case .command:
            return "Command-"
        case .shift:
            return "Shift-"
        case .option:
            return "Option-"
        case .control:
            return "Control-"
        }
    }

    var eventModifier: EventModifiers {
        switch self {
        case .command:
            return .command
        case .shift:
            return .shift
        case .option:
            return .option
        case .control:
            return .control
        }
    }
}

public enum ShortcutDefinition {
    public static let customizableActions = ShortcutAction.allCases

    public static let defaultBindings: [ShortcutAction: ShortcutBinding] = [
        .newScreenshot: ShortcutBinding(key: "S", modifiers: [.command, .shift]),
        .newRecording: ShortcutBinding(key: "R", modifiers: [.command, .shift]),
        .textExtraction: ShortcutBinding(key: "T", modifiers: [.command, .shift]),
        .colorPicker: ShortcutBinding(key: "C", modifiers: [.command, .shift]),
        .lastCapture: ShortcutBinding(key: "L", modifiers: [.command, .shift]),
        .openSettings: ShortcutBinding(key: ",", modifiers: [.command])
    ]

    public static func defaultBinding(for action: ShortcutAction) -> ShortcutBinding {
        defaultBindings[action]!
    }
}
