public struct WidgetVisibilityState: Equatable, Sendable {
    private var configuredEnabled: Bool
    private var manualOverride: Bool?

    public init(configuredEnabled: Bool) {
        self.configuredEnabled = configuredEnabled
    }

    public var isVisible: Bool {
        manualOverride ?? configuredEnabled
    }

    public mutating func toggleManually() {
        manualOverride = !isVisible
    }

    public mutating func updateConfiguredEnabled(_ isEnabled: Bool) {
        guard configuredEnabled != isEnabled else { return }
        configuredEnabled = isEnabled
        manualOverride = nil
    }
}
