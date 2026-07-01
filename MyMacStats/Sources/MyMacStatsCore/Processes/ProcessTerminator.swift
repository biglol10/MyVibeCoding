import Darwin
import Foundation

public struct ProcessTerminationAvailability: Equatable, Sendable {
    public let isAllowed: Bool
    public let reason: String?

    public static let allowed = ProcessTerminationAvailability(isAllowed: true, reason: nil)

    public static func denied(_ reason: String) -> ProcessTerminationAvailability {
        ProcessTerminationAvailability(isAllowed: false, reason: reason)
    }
}

public enum ProcessTerminationError: Error, Equatable, Sendable {
    case protectedProcess(String)
    case permissionDenied
    case processNotFound
    case failed(Int32)

    public var message: String {
        switch self {
        case .protectedProcess(let reason):
            reason
        case .permissionDenied:
            "Permission denied. macOS would not allow MyMacStats to terminate this process."
        case .processNotFound:
            "The process already exited."
        case .failed(let code):
            "Termination failed with errno \(code)."
        }
    }
}

public enum ProcessTerminationMode: Equatable, Sendable {
    case quit
    case forceQuit

    public var signal: Int32 {
        switch self {
        case .quit: SIGTERM
        case .forceQuit: SIGKILL
        }
    }
}

public struct ProcessTerminator {
    private let currentProcessID: Int32
    private let signalSender: (Int32, Int32) -> Int32
    private let errnoProvider: () -> Int32

    public init(
        currentProcessID: Int32 = ProcessInfo.processInfo.processIdentifier,
        signalSender: @escaping (Int32, Int32) -> Int32 = { pid, signal in kill(pid, signal) },
        errnoProvider: @escaping () -> Int32 = { errno }
    ) {
        self.currentProcessID = currentProcessID
        self.signalSender = signalSender
        self.errnoProvider = errnoProvider
    }

    public func canTerminate(_ process: ProcessMetric) -> ProcessTerminationAvailability {
        if process.pid <= 1 {
            return .denied("Protected system process")
        }
        if process.pid == currentProcessID || process.name == "MyMacStatsApp" {
            return .denied("MyMacStats cannot terminate itself")
        }
        if process.name == "launchd" || process.name == "kernel_task" {
            return .denied("Protected system process")
        }
        if let path = process.path, isProtectedSystemPath(path) {
            return .denied("Protected system process")
        }
        return .allowed
    }

    public func canTerminate(_ processes: [ProcessMetric]) -> ProcessTerminationAvailability {
        guard !processes.isEmpty else {
            return .denied("No process selected")
        }
        if let denied = processes
            .map(canTerminate)
            .first(where: { !$0.isAllowed }) {
            return denied
        }
        return .allowed
    }

    private func isProtectedSystemPath(_ path: String) -> Bool {
        let protectedPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/bin/", "/sbin/"]
        return protectedPrefixes.contains { path.hasPrefix($0) }
    }

    public mutating func terminate(_ process: ProcessMetric, mode: ProcessTerminationMode = .quit) throws {
        let availability = canTerminate(process)
        guard availability.isAllowed else {
            throw ProcessTerminationError.protectedProcess(availability.reason ?? "Protected process")
        }

        let result = signalSender(process.pid, mode.signal)
        guard result == 0 else {
            let code = errnoProvider()
            switch code {
            case EPERM:
                throw ProcessTerminationError.permissionDenied
            case ESRCH:
                throw ProcessTerminationError.processNotFound
            default:
                throw ProcessTerminationError.failed(code)
            }
        }
    }

    public mutating func terminate(_ processes: [ProcessMetric], mode: ProcessTerminationMode = .quit) throws {
        let availability = canTerminate(processes)
        guard availability.isAllowed else {
            throw ProcessTerminationError.protectedProcess(availability.reason ?? "Protected process")
        }

        var firstFailure: ProcessTerminationError?
        for process in processes {
            do {
                try terminate(process, mode: mode)
            } catch ProcessTerminationError.processNotFound {
                continue
            } catch let error as ProcessTerminationError {
                if firstFailure == nil {
                    firstFailure = error
                }
            }
        }

        if let firstFailure {
            throw firstFailure
        }
    }
}
