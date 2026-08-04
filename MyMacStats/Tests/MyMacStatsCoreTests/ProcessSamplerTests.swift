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

    func testDefaultResolverReadsBundleIdentifierFromOwningAppInfoPlist() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let app = root.appendingPathComponent("Demo.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let executable = contents.appendingPathComponent("MacOS/Demo")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleIdentifier</key>
          <string>com.example.Demo</string>
        </dict>
        </plist>
        """.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        try Data().write(to: executable)

        let sampler = ProcessSampler(commandRunner: {
            "123 1.0 256 \(executable.path)"
        })

        let processes = try sampler.sample()

        XCTAssertEqual(processes.first?.bundleIdentifier, "com.example.Demo")
    }

    func testDefaultResolverIgnoresNonApplicationBundleExecutables() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let framework = root.appendingPathComponent("MediaLibrary.framework/Versions/A", isDirectory: true)
        let executable = framework.appendingPathComponent("Support/MediaLibraryAgent")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleIdentifier</key>
          <string>com.apple.MediaLibrary</string>
        </dict>
        </plist>
        """.write(to: framework.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        try Data().write(to: executable)

        let sampler = ProcessSampler(commandRunner: {
            "124 1.0 256 \(executable.path)"
        })

        let processes = try sampler.sample()

        XCTAssertNil(processes.first?.bundleIdentifier)
    }
}
