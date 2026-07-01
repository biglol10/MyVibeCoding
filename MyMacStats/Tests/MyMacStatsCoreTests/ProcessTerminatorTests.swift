import XCTest
@testable import MyMacStatsCore

final class ProcessTerminatorTests: XCTestCase {
    func testProtectsSystemAndCurrentAppProcesses() {
        let terminator = ProcessTerminator(currentProcessID: 99)

        XCTAssertFalse(terminator.canTerminate(ProcessMetric(pid: 1, name: "launchd", cpuPercent: 0, memoryBytes: 0, path: "/sbin/launchd", bundleIdentifier: nil)).isAllowed)
        XCTAssertFalse(terminator.canTerminate(ProcessMetric(pid: 99, name: "MyMacStatsApp", cpuPercent: 0, memoryBytes: 0, path: "/Applications/MyMacStats.app", bundleIdentifier: nil)).isAllowed)
        XCTAssertFalse(terminator.canTerminate(ProcessMetric(pid: 150, name: "WindowServer", cpuPercent: 0, memoryBytes: 0, path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", bundleIdentifier: nil)).isAllowed)
        XCTAssertFalse(terminator.canTerminate(ProcessMetric(pid: 151, name: "notifyd", cpuPercent: 0, memoryBytes: 0, path: "/usr/sbin/notifyd", bundleIdentifier: nil)).isAllowed)
        XCTAssertFalse(terminator.canTerminate(ProcessMetric(pid: 152, name: "sleep", cpuPercent: 0, memoryBytes: 0, path: "/bin/sleep", bundleIdentifier: nil)).isAllowed)
    }

    func testAllowsRegularUserProcesses() {
        let terminator = ProcessTerminator(currentProcessID: 99)
        let process = ProcessMetric(pid: 500, name: "Safari", cpuPercent: 3, memoryBytes: 10, path: "/Applications/Safari.app", bundleIdentifier: "com.apple.Safari")

        XCTAssertTrue(terminator.canTerminate(process).isAllowed)
    }

    func testTerminateSendsSIGTERMToAllowedProcess() {
        var sent: [(Int32, Int32)] = []
        var terminator = ProcessTerminator(
            currentProcessID: 99,
            signalSender: { pid, signal in
                sent.append((pid, signal))
                return 0
            },
            errnoProvider: { 0 }
        )
        let process = ProcessMetric(pid: 500, name: "Safari", cpuPercent: 3, memoryBytes: 10, path: "/Applications/Safari.app", bundleIdentifier: "com.apple.Safari")

        XCTAssertNoThrow(try terminator.terminate(process))
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.0, 500)
        XCTAssertEqual(sent.first?.1, SIGTERM)
    }

    func testForceTerminateSendsSIGKILLToAllowedProcess() {
        var sent: [(Int32, Int32)] = []
        var terminator = ProcessTerminator(
            currentProcessID: 99,
            signalSender: { pid, signal in
                sent.append((pid, signal))
                return 0
            },
            errnoProvider: { 0 }
        )
        let process = ProcessMetric(pid: 500, name: "Safari", cpuPercent: 3, memoryBytes: 10, path: "/Applications/Safari.app", bundleIdentifier: "com.apple.Safari")

        XCTAssertNoThrow(try terminator.terminate(process, mode: .forceQuit))
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.0, 500)
        XCTAssertEqual(sent.first?.1, SIGKILL)
    }

    func testGroupTerminationContinuesPastAlreadyExitedProcess() {
        var sent: [(Int32, Int32)] = []
        var terminator = ProcessTerminator(
            currentProcessID: 99,
            signalSender: { pid, signal in
                sent.append((pid, signal))
                return pid == 501 ? -1 : 0
            },
            errnoProvider: { ESRCH }
        )
        let staleHelper = ProcessMetric(pid: 501, name: "Figma Helper", cpuPercent: 5, memoryBytes: 10, path: "/Applications/Figma.app/Contents/Frameworks/Figma Helper.app", bundleIdentifier: "com.figma.Desktop.helper")
        let mainApp = ProcessMetric(pid: 500, name: "Figma", cpuPercent: 3, memoryBytes: 10, path: "/Applications/Figma.app/Contents/MacOS/Figma", bundleIdentifier: "com.figma.Desktop")

        XCTAssertNoThrow(try terminator.terminate([staleHelper, mainApp]))
        XCTAssertEqual(sent.map(\.0), [501, 500])
        XCTAssertTrue(sent.allSatisfy { $0.1 == SIGTERM })
    }

    func testTerminateReportsProtectedAndPermissionFailures() {
        var protectedTerminator = ProcessTerminator(currentProcessID: 99)
        let protected = ProcessMetric(pid: 1, name: "launchd", cpuPercent: 0, memoryBytes: 0, path: "/sbin/launchd", bundleIdentifier: nil)
        XCTAssertThrowsError(try protectedTerminator.terminate(protected)) { error in
            XCTAssertEqual(error as? ProcessTerminationError, .protectedProcess("Protected system process"))
        }

        var permissionTerminator = ProcessTerminator(
            currentProcessID: 99,
            signalSender: { _, _ in -1 },
            errnoProvider: { EPERM }
        )
        let normal = ProcessMetric(pid: 500, name: "Safari", cpuPercent: 3, memoryBytes: 10, path: "/Applications/Safari.app", bundleIdentifier: "com.apple.Safari")
        XCTAssertThrowsError(try permissionTerminator.terminate(normal)) { error in
            XCTAssertEqual(error as? ProcessTerminationError, .permissionDenied)
        }
    }
}
