import XCTest
@testable import MyMacStatsCore

final class ProcessCommandTests: XCTestCase {
    func testRunDrainsLargeStandardOutputWithoutDeadlock() {
        let finished = expectation(description: "large output command finishes")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let output = try ProcessCommand.run(
                    "/usr/bin/python3",
                    arguments: ["-c", "import sys; sys.stdout.write('x' * 200000)"]
                )
                XCTAssertEqual(output.count, 200_000)
            } catch {
                XCTFail("Expected command to finish, got \(error)")
            }
            finished.fulfill()
        }

        wait(for: [finished], timeout: 3)
    }
}
