import SwiftUI
import XCTest
@testable import MyMacFinder

@MainActor
final class PrivacyAccessSettingsViewTests: XCTestCase {
    func testPrivacyAccessSettingsViewBuildsForEmptyFolderGrants() {
        let view = PrivacyAccessSettingsView(
            sandboxPolicy: SandboxPolicySummary(isSandboxed: false),
            grantedFolderSummaries: [],
            onChooseFolder: {},
            onOpenPrivacySettings: {},
            onRemoveGrant: { _ in },
            onResetGrants: {}
        )

        XCTAssertNotNil(String(describing: view))
    }

    func testPrivacyAccessSettingsViewBuildsForGrantedFolders() {
        let view = PrivacyAccessSettingsView(
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            grantedFolderSummaries: [
                FolderAccessGrantSummary(
                    grant: FolderAccessGrant(
                        url: URL(fileURLWithPath: "/Users/biglol/Documents/Work", isDirectory: true),
                        bookmarkData: Data()
                    )
                )
            ],
            onChooseFolder: {},
            onOpenPrivacySettings: {},
            onRemoveGrant: { _ in },
            onResetGrants: {}
        )

        XCTAssertNotNil(String(describing: view))
    }
}
