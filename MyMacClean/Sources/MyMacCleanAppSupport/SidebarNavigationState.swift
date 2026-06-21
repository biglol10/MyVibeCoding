public struct SidebarNavigationState: Equatable, Sendable {
    public private(set) var selectedDestination: SidebarDestination

    public init(selectedDestination: SidebarDestination = .applications) {
        self.selectedDestination = selectedDestination
    }

    public mutating func select(_ destination: SidebarDestination) {
        selectedDestination = destination
    }

    public var activeTitle: String {
        selectedDestination.title
    }

    public var activeActionTitle: String {
        selectedDestination.primaryActionTitle
    }
}
