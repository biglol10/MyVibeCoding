import SwiftUI
import XCTest
@testable import MyMacFinder

@MainActor
final class PrivacyAccessSettingsViewTests: XCTestCase {
    func testPrivacyAccessSettingsPresentationDescribesEmptyFolderGrants() {
        let presentation = PrivacyAccessSettingsPresentation(
            sandboxPolicy: SandboxPolicySummary(isSandboxed: false),
            grantedFolderSummaries: []
        )

        XCTAssertEqual(presentation.folderCountText, "0 folders")
        XCTAssertFalse(presentation.showsResetAction)
        XCTAssertEqual(presentation.emptyTitle, "No folders selected")
        XCTAssertEqual(presentation.folderRows, [])
    }

    func testPrivacyAccessSettingsPresentationDescribesGrantedFolders() {
        let availableGrant = FolderAccessGrantSummary(
            grant: FolderAccessGrant(
                url: URL(fileURLWithPath: "/Users/biglol/Documents/Work", isDirectory: true),
                bookmarkData: Data()
            ),
            availability: .available
        )
        let staleGrant = FolderAccessGrantSummary(
            grant: FolderAccessGrant(
                url: URL(fileURLWithPath: "/Users/biglol/Documents/Archive", isDirectory: true),
                bookmarkData: Data()
            ),
            availability: .available,
            isStale: true
        )
        let unavailableGrant = FolderAccessGrantSummary(
            grant: FolderAccessGrant(
                url: URL(fileURLWithPath: "/Users/biglol/Documents/Missing", isDirectory: true),
                bookmarkData: Data()
            ),
            availability: .unavailable
        )
        let presentation = PrivacyAccessSettingsPresentation(
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            grantedFolderSummaries: [availableGrant, staleGrant, unavailableGrant]
        )

        XCTAssertEqual(presentation.folderCountText, "3 folders")
        XCTAssertTrue(presentation.showsResetAction)
        XCTAssertEqual(presentation.folderRows.map(\.statusText), [
            "Available",
            "Bookmark refreshed",
            "Needs selection again"
        ])
        XCTAssertEqual(presentation.folderRows.map(\.systemImageName), [
            "checkmark.circle.fill",
            "checkmark.circle.fill",
            "exclamationmark.triangle.fill"
        ])
    }

    func testPrivacyAccessSettingsPresentationOffersResetForPersistenceError() {
        let presentation = PrivacyAccessSettingsPresentation(
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            grantedFolderSummaries: [],
            persistenceErrorMessage: "Saved folder access data is damaged."
        )

        XCTAssertTrue(presentation.showsPersistenceError)
        XCTAssertTrue(presentation.showsResetAction)
        XCTAssertEqual(
            presentation.persistenceErrorMessage,
            "Saved folder access data is damaged."
        )
    }
}
