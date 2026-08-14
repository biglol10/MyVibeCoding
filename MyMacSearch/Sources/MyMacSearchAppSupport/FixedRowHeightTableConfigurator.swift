import AppKit

public enum FixedRowHeightTableConfigurator {
    @MainActor
    @discardableResult
    public static func configure(
        descendantsOf rootView: NSView,
        matchingColumnCount: Int,
        rowHeight: CGFloat
    ) -> Int {
        var configuredCount = 0

        func visit(_ view: NSView) {
            if let tableView = view as? NSTableView,
               tableView.tableColumns.count == matchingColumnCount {
                tableView.usesAutomaticRowHeights = false
                tableView.rowHeight = rowHeight
                configuredCount += 1
            }
            for subview in view.subviews {
                visit(subview)
            }
        }

        visit(rootView)
        return configuredCount
    }
}
