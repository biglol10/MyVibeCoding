import AppKit
import XCTest
@testable import MyMacSearchAppSupport

final class FixedRowHeightTableConfiguratorTests: XCTestCase {
    @MainActor
    func testConfigureDisablesAutomaticHeightOnlyForMatchingTable() {
        let root = NSView()
        let resultsTable = makeTable(columnCount: 5)
        let sidebarTable = makeTable(columnCount: 1)
        root.addSubview(resultsTable)
        root.addSubview(sidebarTable)

        let configuredCount = FixedRowHeightTableConfigurator.configure(
            descendantsOf: root,
            matchingColumnCount: 5,
            rowHeight: 22
        )

        XCTAssertEqual(configuredCount, 1)
        XCTAssertFalse(resultsTable.usesAutomaticRowHeights)
        XCTAssertEqual(resultsTable.rowHeight, 22)
        XCTAssertTrue(sidebarTable.usesAutomaticRowHeights)
    }

    @MainActor
    private func makeTable(columnCount: Int) -> NSTableView {
        let table = NSTableView()
        table.usesAutomaticRowHeights = true
        for index in 0..<columnCount {
            table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column-\(index)")))
        }
        return table
    }
}
