import Foundation

public enum ApplicationCleanupMode: String, CaseIterable, Identifiable, Sendable {
    case uninstall
    case resetData

    public var id: Self { self }

    public var title: String {
        switch self {
        case .uninstall: "Uninstall"
        case .resetData: "Reset Data"
        }
    }

    public var confirmationPhrase: String {
        switch self {
        case .uninstall: "DELETE"
        case .resetData: "RESET"
        }
    }

    public var isTrashOnly: Bool {
        self == .resetData
    }
}
