import XCTest
import CoreServices
@testable import MyMacSearchCore

final class FileEventPlannerTests: XCTestCase {
    func testCoalescesOrdinaryEventsByPathAndKeepsLatestCheckpoint() {
        let events = [
            FileEvent(path: "/scope/Report.pdf", eventID: 10, flags: [.created]),
            FileEvent(path: "/scope/Report.pdf", eventID: 11, flags: [.modified]),
            FileEvent(path: "/scope/Old.txt", eventID: 12, flags: [.removed])
        ]

        let plan = FileEventPlanner.plan(events: events, scopeRoot: "/scope")

        XCTAssertEqual(plan.upsertPaths, ["/scope/Report.pdf"])
        XCTAssertEqual(plan.deletePaths, ["/scope/Old.txt"])
        XCTAssertEqual(plan.reconcileRoots, [])
        XCTAssertEqual(plan.latestEventID, 12)
        XCTAssertFalse(plan.requiresFullReconciliation)
    }

    func testLaterCreateSupersedesRemovalForSamePath() {
        let events = [
            FileEvent(path: "/scope/item", eventID: 20, flags: [.removed]),
            FileEvent(path: "/scope/item", eventID: 21, flags: [.created])
        ]

        let plan = FileEventPlanner.plan(events: events, scopeRoot: "/scope")

        XCTAssertEqual(plan.upsertPaths, ["/scope/item"])
        XCTAssertEqual(plan.deletePaths, [])
    }

    func testRenamesReconcileParentBecauseOldNameMayBeAbsent() {
        let plan = FileEventPlanner.plan(
            events: [FileEvent(path: "/scope/folder/new.txt", eventID: 30, flags: [.renamed])],
            scopeRoot: "/scope"
        )

        XCTAssertEqual(plan.reconcileRoots, ["/scope/folder"])
        XCTAssertEqual(plan.upsertPaths, [])
        XCTAssertEqual(plan.deletePaths, [])
    }

    func testDroppedEventsRequireFullScopeReconciliationWithoutGuessedMutations() {
        let plan = FileEventPlanner.plan(
            events: [
                FileEvent(path: "/scope/partial", eventID: 40, flags: [.modified]),
                FileEvent(path: "/scope", eventID: 41, flags: [.kernelDropped])
            ],
            scopeRoot: "/scope"
        )

        XCTAssertTrue(plan.requiresFullReconciliation)
        XCTAssertEqual(plan.reconcileRoots, ["/scope"])
        XCTAssertEqual(plan.upsertPaths, [])
        XCTAssertEqual(plan.deletePaths, [])
        XCTAssertEqual(plan.latestEventID, 41)
    }

    func testEventsOutsideScopeAreIgnored() {
        let plan = FileEventPlanner.plan(
            events: [FileEvent(path: "/scope-two/file", eventID: 50, flags: [.created])],
            scopeRoot: "/scope"
        )

        XCTAssertEqual(plan, FileEventPlan(latestEventID: 50))
    }

    func testFSEventFlagsMapLossAndItemChanges() {
        let raw = FSEventStreamEventFlags(
            kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagItemCreated
        )

        let flags = FSEventsWatcher.flags(fromRawValue: raw)

        XCTAssertTrue(flags.contains(.kernelDropped))
        XCTAssertTrue(flags.contains(.mustScanSubDirectories))
        XCTAssertTrue(flags.contains(.created))
        XCTAssertFalse(flags.contains(.removed))
    }
}
