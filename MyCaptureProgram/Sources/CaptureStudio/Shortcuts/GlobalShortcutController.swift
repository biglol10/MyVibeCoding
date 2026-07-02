import Carbon
import Combine
import Foundation

public enum GlobalShortcutRegistrationError: LocalizedError, Equatable {
    case unsupportedKey(String)
    case registerFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unsupportedKey(let key):
            return "The key '\(key)' is not supported for global shortcuts."
        case .registerFailed(let status):
            return "Global shortcut registration failed (\(status))."
        }
    }
}

public protocol GlobalShortcutRegistering: AnyObject {
    func registerHotKey(
        action: ShortcutAction,
        binding: ShortcutBinding,
        handler: @escaping @MainActor () -> Void
    ) throws
    func unregisterAll()
}

@MainActor
public final class GlobalShortcutController: ObservableObject {
    private let registrar: GlobalShortcutRegistering
    private var shortcutManager: ShortcutManager?
    private var actionHandler: ((ShortcutAction) -> Void)?
    private var bindingsCancellable: AnyCancellable?
    private var isConfigured = false

    public init(registrar: GlobalShortcutRegistering? = nil) {
        self.registrar = registrar ?? CarbonGlobalShortcutRegistrar()
    }

    public func configure(
        shortcutManager: ShortcutManager,
        actionHandler: @escaping (ShortcutAction) -> Void
    ) {
        guard !isConfigured else {
            return
        }

        self.shortcutManager = shortcutManager
        self.actionHandler = actionHandler
        self.isConfigured = true

        bindingsCancellable = shortcutManager.$bindings.sink { [weak self] bindings in
            self?.refreshRegistrations(using: bindings)
        }

        refreshRegistrations(using: shortcutManager.bindings)
    }

    private func refreshRegistrations(using bindings: [ShortcutAction: ShortcutBinding]) {
        guard let shortcutManager, let actionHandler else {
            return
        }

        registrar.unregisterAll()
        shortcutManager.clearAllRegistrationFailures()

        for action in ShortcutDefinition.globalActions {
            guard let binding = bindings[action] else {
                continue
            }

            do {
                try registrar.registerHotKey(action: action, binding: binding) {
                    actionHandler(action)
                }
                shortcutManager.clearRegistrationFailure(for: action)
            } catch let error as GlobalShortcutRegistrationError {
                shortcutManager.markRegistrationFailed(
                    for: action,
                    reason: error.errorDescription ?? "Registration failed."
                )
            } catch {
                shortcutManager.markRegistrationFailed(
                    for: action,
                    reason: error.localizedDescription
                )
            }
        }
    }
}

private final class CarbonGlobalShortcutRegistrar: GlobalShortcutRegistering {
    private let signature: OSType = 0x43535444 // CSTD
    private var hotKeyRefs: [ShortcutAction: EventHotKeyRef] = [:]
    private var handlers: [UInt32: @MainActor () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?

    init() {
        installHandlerIfNeeded()
    }

    deinit {
        unregisterAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func registerHotKey(
        action: ShortcutAction,
        binding: ShortcutBinding,
        handler: @escaping @MainActor () -> Void
    ) throws {
        let keyCode = try ShortcutKeyCodeMap.keyCode(for: binding.key)
        let modifiers = ShortcutKeyCodeMap.carbonModifiers(for: binding.modifiers)
        unregister(action: action)

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: action.hotKeyID)
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            throw GlobalShortcutRegistrationError.registerFailed(status)
        }

        hotKeyRefs[action] = hotKeyRef
        handlers[action.hotKeyID] = handler
    }

    func unregisterAll() {
        for action in Array(hotKeyRefs.keys) {
            unregister(action: action)
        }
    }

    private func unregister(action: ShortcutAction) {
        if let hotKeyRef = hotKeyRefs.removeValue(forKey: action) {
            UnregisterEventHotKey(hotKeyRef)
        }
        handlers[action.hotKeyID] = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let userData,
                  let eventRef
            else {
                return noErr
            }

            let registrar = Unmanaged<CarbonGlobalShortcutRegistrar>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, let handler = registrar.handlers[hotKeyID.id] else {
                return noErr
            }

            Task { @MainActor in
                handler()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )
    }
}

private enum ShortcutKeyCodeMap {
    private static let keyCodes: [String: UInt32] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9,
        "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16, "T": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "O": 31, "U": 32, "[": 33, "I": 34, "P": 35, "L": 37, "J": 38,
        "'": 39, "K": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "N": 45, "M": 46, ".": 47,
        "`": 50
    ]

    static func keyCode(for key: String) throws -> UInt32 {
        let normalized = key.uppercased()
        guard let keyCode = keyCodes[normalized] else {
            throw GlobalShortcutRegistrationError.unsupportedKey(key)
        }
        return keyCode
    }

    static func carbonModifiers(for modifiers: [ShortcutModifier]) -> UInt32 {
        modifiers.reduce(into: UInt32(0)) { result, modifier in
            switch modifier {
            case .command:
                result |= UInt32(cmdKey)
            case .shift:
                result |= UInt32(shiftKey)
            case .option:
                result |= UInt32(optionKey)
            case .control:
                result |= UInt32(controlKey)
            }
        }
    }
}

private extension ShortcutAction {
    var hotKeyID: UInt32 {
        switch self {
        case .newScreenshot:
            return 1
        case .newRecording:
            return 2
        case .openSettings:
            return 3
        case .textExtraction:
            return 4
        case .colorPicker:
            return 5
        case .lastCapture:
            return 6
        }
    }
}
