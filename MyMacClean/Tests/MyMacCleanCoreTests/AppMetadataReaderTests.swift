import XCTest
@testable import MyMacCleanCore

final class AppMetadataReaderTests: XCTestCase {
    func testReadsMetadataFromInfoPlistAndComputesBundleSize() throws {
        let root = try TestFixtures.temporaryDirectory(named: "metadata")
        let appURL = try TestFixtures.makeAppBundle(
            root: root,
            name: "Figma",
            bundleIdentifier: "com.figma.Desktop",
            version: "124.1",
            executableName: "FigmaDesktop",
            payloadSize: 5
        )

        let app = try AppMetadataReader().readApp(at: appURL)

        XCTAssertEqual(app.displayName, "Figma")
        XCTAssertEqual(app.bundleIdentifier, "com.figma.Desktop")
        XCTAssertEqual(app.version, "124.1")
        XCTAssertEqual(app.executableName, "FigmaDesktop")
        XCTAssertEqual(app.bundleURL, appURL)
        XCTAssertGreaterThanOrEqual(app.bundleSize, 5)
    }
}
