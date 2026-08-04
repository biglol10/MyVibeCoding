import AppKit
import MyMacStatsCore

public protocol ApplicationTerminating: AnyObject {
    func terminateApplicationProcesses(_ processes: [ProcessMetric], mode: ProcessTerminationMode) -> Bool
}

public final class RunningApplicationTerminator: ApplicationTerminating {
    public init() {}

    public func terminateApplicationProcesses(_ processes: [ProcessMetric], mode: ProcessTerminationMode) -> Bool {
        var attempted = false
        var seenPIDs = Set<Int32>()

        for process in processes where seenPIDs.insert(process.pid).inserted {
            guard let runningApplication = NSRunningApplication(processIdentifier: process.pid) else {
                continue
            }

            let accepted: Bool
            switch mode {
            case .quit:
                accepted = runningApplication.terminate()
            case .forceQuit:
                accepted = runningApplication.forceTerminate()
            }
            attempted = attempted || accepted
        }

        return attempted
    }
}
