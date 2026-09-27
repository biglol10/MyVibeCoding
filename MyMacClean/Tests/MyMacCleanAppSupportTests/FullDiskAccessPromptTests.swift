import Foundation
import MyMacCleanCore
import XCTest
@testable import MyMacCleanAppSupport

final class FullDiskAccessPromptTests: XCTestCase {
    func testProbeReportsMissingWhenProtectedDirectoryThrowsPermissionDenied() {
        let protectedURL = URL(fileURLWithPath: "/Users/me/Library/Mail", isDirectory: true)
        let probe = FullDiskAccessProbe(protectedURLs: [protectedURL]) { _ in
            throw CocoaError(.fileReadNoPermission)
        }

        XCTAssertEqual(probe.status(), .missing)
    }

    func testProbeReportsGrantedWhenProtectedDirectoryCanBeRead() {
        let protectedURL = URL(fileURLWithPath: "/Users/me/Library/Mail", isDirectory: true)
        let probe = FullDiskAccessProbe(protectedURLs: [protectedURL]) { _ in
            [protectedURL.appendingPathComponent("V10", isDirectory: true)]
        }

        XCTAssertEqual(probe.status(), .granted)
    }

    func testProbeReportsUndeterminedWhenProtectedDirectoryDoesNotExist() {
        let protectedURL = URL(fileURLWithPath: "/Users/me/Library/Mail", isDirectory: true)
        let probe = FullDiskAccessProbe(protectedURLs: [protectedURL]) { _ in
            throw CocoaError(.fileNoSuchFile)
        }

        XCTAssertEqual(probe.status(), .undetermined)
    }

    func testPromptPresentationOpensFullDiskAccessSettings() throws {
        let presentation = FullDiskAccessPromptPresentation(appName: "MyMacClean")

        XCTAssertEqual(presentation.title, "Full Disk Access Required")
        XCTAssertTrue(presentation.message.contains("MyMacClean"))
        XCTAssertTrue(presentation.message.contains("restart"))
        XCTAssertEqual(presentation.settingsURL.scheme, "x-apple.systempreferences")
        XCTAssertTrue(presentation.settingsURL.absoluteString.contains("Privacy_AllFiles"))
    }

    func testAppManagementPromptExplainsAppBundlePermission() throws {
        let presentation = AppManagementPromptPresentation(appName: "MyMacClean")

        XCTAssertEqual(presentation.title, "App Management Permission May Be Needed")
        XCTAssertTrue(presentation.message.contains("App Management"))
        XCTAssertTrue(presentation.message.contains("administrator"))
        XCTAssertEqual(presentation.primaryButtonTitle, "Open App Management Settings")
        XCTAssertEqual(presentation.cancelButtonTitle, "Cancel")
        XCTAssertEqual(presentation.settingsURL.scheme, "x-apple.systempreferences")
        XCTAssertTrue(presentation.settingsURL.absoluteString.contains("Privacy_AppBundles"))
    }
}
