import XCTest
@testable import MyMacStatsCore

final class ProcessSamplerTests: XCTestCase {
    func testCachesBundleIdentifierResolutionByPath() throws {
        var resolveCount = 0
        let output = """
          100   1.0   1024 /Applications/Test.app/Contents/MacOS/Test
          101   2.0   2048 /Applications/Test.app/Contents/MacOS/Test
        """
        let sampler = ProcessSampler(
            commandRunner: { output },
            bundleIdentifierResolver: { _ in
                resolveCount += 1
                return "com.example.Test"
            }
        )

        let processes = try sampler.sample()

        XCTAssertEqual(processes.count, 2)
        XCTAssertEqual(resolveCount, 1)
        XCTAssertEqual(Set(processes.compactMap(\.bundleIdentifier)), ["com.example.Test"])
    }
}
