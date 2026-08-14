import Carbon
import Foundation

public enum GlobalShortcutError: Error, LocalizedError, Equatable, Sendable {
    case registrationFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "The global shortcut could not be registered (error \(status))."
        }
    }
}

public struct HotKeyRegistration {
    public let id: UInt32
    public let opaqueReference: EventHotKeyRef?

    public init(id: UInt32, opaqueReference: EventHotKeyRef?) {
        self.id = id
        self.opaqueReference = opaqueReference
    }
}

@MainActor
public protocol HotKeyRegistering: AnyObject {
    func register(
        id: UInt32,
        setting: GlobalShortcutSetting,
        onPressed: @escaping @MainActor () -> Void
    ) throws -> HotKeyRegistration
    func unregister(_ registration: HotKeyRegistration)
}

@MainActor
public final class GlobalShortcutController {
    public private(set) var isRegistered = false

    private let registrar: any HotKeyRegistering
    private var registration: HotKeyRegistration?
    private var nextID: UInt32 = 1

    public init(registrar: any HotKeyRegistering = CarbonHotKeyRegistrar()) {
        self.registrar = registrar
    }

    deinit {
        MainActor.assumeIsolated {
            unregister()
        }
    }

    public func register(
        _ setting: GlobalShortcutSetting,
        onPressed: @escaping @MainActor () -> Void
    ) throws {
        unregister()
        let id = nextID
        nextID &+= 1
        do {
            registration = try registrar.register(
                id: id,
                setting: setting,
                onPressed: onPressed
            )
            isRegistered = true
        } catch {
            registration = nil
            isRegistered = false
            throw error
        }
    }

    public func unregister() {
        if let registration {
            registrar.unregister(registration)
        }
        registration = nil
        isRegistered = false
    }
}

@MainActor
public final class CarbonHotKeyRegistrar: HotKeyRegistering {
    private struct OwnedRegistration {
        let callbackBox: CallbackBox
        let eventHandler: EventHandlerRef?
    }

    private var owned: [UInt32: OwnedRegistration] = [:]

    public init() {}

    public func register(
        id: UInt32,
        setting: GlobalShortcutSetting,
        onPressed: @escaping @MainActor () -> Void
    ) throws -> HotKeyRegistration {
        let callbackBox = CallbackBox(onPressed: onPressed)
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var eventHandler: EventHandlerRef?
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(callbackBox).toOpaque())
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let box = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in
                    box.onPressed()
                }
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandler
        )
        guard handlerStatus == noErr else {
            throw GlobalShortcutError.registrationFailed(handlerStatus)
        }

        var hotKeyReference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let registrationStatus = RegisterEventHotKey(
            setting.keyCode,
            setting.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard registrationStatus == noErr else {
            if let eventHandler { RemoveEventHandler(eventHandler) }
            throw GlobalShortcutError.registrationFailed(registrationStatus)
        }

        owned[id] = OwnedRegistration(
            callbackBox: callbackBox,
            eventHandler: eventHandler
        )
        return HotKeyRegistration(id: id, opaqueReference: hotKeyReference)
    }

    public func unregister(_ registration: HotKeyRegistration) {
        if let reference = registration.opaqueReference {
            UnregisterEventHotKey(reference)
        }
        if let eventHandler = owned.removeValue(forKey: registration.id)?.eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private static let signature: OSType = 0x4D4D_5348 // MMSH

    private final class CallbackBox {
        let onPressed: @MainActor () -> Void

        init(onPressed: @escaping @MainActor () -> Void) {
            self.onPressed = onPressed
        }
    }
}
