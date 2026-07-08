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

    func testFinderAutomationPromptExplainsFinderTrashFallback() throws {
        let presentation = FinderAutomationPromptPresentation(appName: "MyMacClean")

        XCTAssertEqual(presentation.title, "Finder Permission May Be Needed")
        XCTAssertTrue(presentation.message.contains("Finder"))
        XCTAssertTrue(presentation.message.contains("Trash"))
        XCTAssertEqual(presentation.primaryButtonTitle, "Continue and Request Finder Permission")
        XCTAssertEqual(presentation.cancelButtonTitle, "Cancel")
        XCTAssertEqual(presentation.settingsURL.scheme, "x-apple.systempreferences")
        XCTAssertTrue(presentation.settingsURL.absoluteString.contains("Privacy_Automation"))
    }

    func testFinderAutomationPromptIsRequiredForApplicationsAppBundleTrashCleanup() {
        let candidate = RelatedFileCandidate(
            url: URL(fileURLWithPath: "/Applications/Cursor.app", isDirectory: true),
            kind: .appBundle,
            size: 0,
            matchReason: "selected app",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )

        XCTAssertTrue(FinderAutomationPromptPresentation.requiresPrompt(candidates: [candidate], mode: .moveToTrash))
    }

    func testFinderAutomationPromptIsNotRequiredForUserApplicationsOrPermanentDeletion() {
        let candidate = RelatedFileCandidate(
            url: URL(fileURLWithPath: "/Users/me/Applications/Cursor.app", isDirectory: true),
            kind: .appBundle,
            size: 0,
            matchReason: "selected app",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )

        XCTAssertFalse(FinderAutomationPromptPresentation.requiresPrompt(candidates: [candidate], mode: .moveToTrash))
        XCTAssertFalse(FinderAutomationPromptPresentation.requiresPrompt(candidates: [candidate], mode: .permanent))
    }
}
