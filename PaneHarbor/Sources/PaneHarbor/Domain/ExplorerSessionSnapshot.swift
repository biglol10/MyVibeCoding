import Foundation

public struct ExplorerSessionPane: Codable, Equatable, Sendable {
    public var location: PaneLocation
    public var sort: EntrySortDescriptor
    public var group: EntryGroupDescriptor?

    public init(
        location: PaneLocation,
        sort: EntrySortDescriptor,
        group: EntryGroupDescriptor?
    ) {
        self.location = location
        self.sort = sort
        self.group = group
    }
}

public struct ExplorerSessionTab: Codable, Equatable, Sendable {
    public var panes: [ExplorerSessionPane]
    public var activePaneIndex: Int

    public init(panes: [ExplorerSessionPane], activePaneIndex: Int) {
        self.panes = panes
        self.activePaneIndex = activePaneIndex
    }
}

public struct ExplorerSessionSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let maximumTabCount = 20

    public var version: Int
    public var tabs: [ExplorerSessionTab]
    public var activeTabIndex: Int

    public init(
        version: Int = ExplorerSessionSnapshot.currentVersion,
        tabs: [ExplorerSessionTab],
        activeTabIndex: Int
    ) {
        self.version = version
        self.tabs = tabs
        self.activeTabIndex = activeTabIndex
    }

    @MainActor
    public func restoredWorkspace(
        fallbackLocation: PaneLocation,
        paneMode: ExplorerPaneMode
    ) -> (tabs: [ExplorerTab], activeTabIndex: Int) {
        let sourceTabs = Array(tabs.prefix(Self.maximumTabCount))
        let restoredTabs = sourceTabs.compactMap { sessionTab -> ExplorerTab? in
            let maximumPaneCount = paneMode == .dual ? 2 : 1
            var panes = Array(sessionTab.panes.prefix(maximumPaneCount)).map { sessionPane in
                var pane = PaneState(location: sessionPane.location, sort: sessionPane.sort)
                pane.group = sessionPane.group
                return pane
            }
            if panes.isEmpty {
                panes = [PaneState(location: fallbackLocation)]
            }
            if paneMode == .dual, panes.count == 1 {
                panes.append(PaneState(location: panes[0].location, sort: panes[0].sort))
            }

            let activePaneIndex = min(max(sessionTab.activePaneIndex, 0), panes.count - 1)
            return ExplorerTab(
                panes: panes,
                activePaneIndex: activePaneIndex,
                pathInput: panes[activePaneIndex].location.displayPath
            )
        }

        let normalizedTabs: [ExplorerTab]
        if restoredTabs.isEmpty {
            normalizedTabs = [
                ExplorerTab(
                    panes: [PaneState(location: fallbackLocation)],
                    activePaneIndex: 0,
                    pathInput: fallbackLocation.displayPath
                )
            ]
        } else {
            normalizedTabs = restoredTabs
        }

        return (
            tabs: normalizedTabs,
            activeTabIndex: min(max(activeTabIndex, 0), normalizedTabs.count - 1)
        )
    }
}
