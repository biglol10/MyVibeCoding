import XCTest
import MyMacCleanCore
@testable import MyMacCleanAppSupport

@MainActor
final class ScanCoverageViewModelTests: XCTestCase {
    func testApplicationViewModelPublishesDiscoveryAndRelatedFileIssuesAlongsideValues() async {
        let app = makeApp()
        let appIssue = ScanIssue(path: "/Applications/Broken.app", message: "Unreadable", permissionRelated: false)
        let relatedIssue = ScanIssue(path: "/Users/test/Library/Caches", message: "Denied", permissionRelated: true)
        let candidate = RelatedFileCandidate(
            url: app.bundleURL,
            kind: .appBundle,
            size: 10,
            matchReason: "selected app bundle",
            confidence: .high,
            defaultSelected: true,
            requiresManualReview: false,
            isProtected: false
        )
        let viewModel = ApplicationListViewModel(
            applicationDiscovering: ApplicationDiscovering {
                ScanResult(value: [app], issues: [appIssue])
            },
            relatedFileScanning: RelatedFileScanning { _ in
                ScanResult(value: [candidate], issues: [relatedIssue])
            }
        )

        await viewModel.loadApps()
        await viewModel.scanSelectedApp()

        XCTAssertEqual(viewModel.apps, [app])
        XCTAssertEqual(viewModel.applicationDiscoveryIssues, [appIssue])
        XCTAssertEqual(viewModel.candidates, [candidate])
        XCTAssertEqual(viewModel.relatedFileScanIssues, [relatedIssue])
    }

    func testOrphanViewModelPublishesIssuesAlongsideGroups() async {
        let candidate = RelatedFileCandidate(
            url: URL(fileURLWithPath: "/Users/test/Library/Caches/com.example.Orphan"),
            kind: .cache,
            size: 10,
            matchReason: "orphan",
            confidence: .high,
            defaultSelected: false,
            requiresManualReview: true,
            isProtected: false
        )
        let group = OrphanFileGroup(
            inferredName: "Example",
            inferredIdentifier: "com.example.Orphan",
            candidates: [candidate]
        )
        let issue = ScanIssue(path: "/Users/test/Library/Preferences", message: "Unreadable", permissionRelated: false)
        let viewModel = OrphanFilesViewModel(
            installedApps: [],
            orphanFileScanning: OrphanFileScanning { _ in
                ScanResult(value: [group], issues: [issue])
            }
        )

        await viewModel.loadGroups()

        XCTAssertEqual(viewModel.groups, [group])
        XCTAssertEqual(viewModel.scanIssues, [issue])
    }

    func testLargeFilesViewModelClearsPreviousIssuesWhenScanCompletes() async {
        let root = URL(fileURLWithPath: "/Users/test/Downloads", isDirectory: true)
        let candidate = LargeFileCandidate(
            url: root.appendingPathComponent("archive.zip"),
            size: 1_000,
            modifiedAt: nil,
            kind: .archive,
            rootURL: root
        )
        let viewModel = LargeFilesViewModel(
            scanRoots: [root],
            minimumSize: 1,
            largeFileScanning: LargeFileScanning { _, _, _ in
                ScanResult(value: [candidate], issues: [])
            }
        )
        viewModel.scanIssues = [
            ScanIssue(path: "/old", message: "Old issue", permissionRelated: false)
        ]

        await viewModel.scan()

        XCTAssertEqual(viewModel.candidates, [candidate])
        XCTAssertTrue(viewModel.scanIssues.isEmpty)
    }

    func testDeveloperCacheViewModelPublishesIssuesAlongsideCandidates() async {
        let candidate = DeveloperCacheCandidate(
            tool: .npm,
            url: URL(fileURLWithPath: "/Users/test/.npm", isDirectory: true),
            size: 10,
            safety: .safe,
            explanation: "Recreated when needed."
        )
        let issue = ScanIssue(path: "/Users/test/.gradle/caches", message: "Denied", permissionRelated: true)
        let viewModel = DeveloperCacheViewModel(
            developerCacheScanning: DeveloperCacheScanning {
                ScanResult(value: [candidate], issues: [issue])
            }
        )

        await viewModel.scan()

        XCTAssertEqual(viewModel.candidates, [candidate])
        XCTAssertEqual(viewModel.scanIssues, [issue])
    }

    func testStartupItemsViewModelPublishesIssuesAlongsideItems() async {
        let item = makeStartupItem()
        let issue = ScanIssue(path: "/Users/test/Library/LaunchAgents/broken.plist", message: "Malformed", permissionRelated: false)
        let viewModel = StartupItemsViewModel(
            startupItemScanning: StartupItemScanning {
                ScanResult(value: [item], issues: [issue])
            }
        )

        await viewModel.scan()

        XCTAssertEqual(viewModel.items, [item])
        XCTAssertEqual(viewModel.scanIssues, [issue])
        XCTAssertEqual(viewModel.selectedItem, item)
    }

    private func makeApp() -> InstalledApp {
        InstalledApp(
            displayName: "Editor",
            bundleIdentifier: "com.example.Editor",
            version: "1.0",
            executableName: "Editor",
            bundleURL: URL(fileURLWithPath: "/Applications/Editor.app", isDirectory: true),
            iconIdentifier: nil,
            bundleSize: 10,
            lastOpenedAt: nil
        )
    }

    private func makeStartupItem() -> StartupItem {
        StartupItem(
            label: "com.example.agent",
            plistURL: URL(fileURLWithPath: "/Users/test/Library/LaunchAgents/com.example.agent.plist"),
            scope: .userLaunchAgent,
            state: .enabled,
            program: "/bin/echo",
            programArguments: [],
            runAtLoad: true,
            keepAliveSummary: nil,
            startInterval: nil,
            startCalendarSummary: nil,
            disabledFlag: false,
            disabledByRename: false,
            targetURL: URL(fileURLWithPath: "/bin/echo"),
            targetExists: true,
            ownerName: "Example",
            ownerEvidence: "Test fixture"
        )
    }
}
