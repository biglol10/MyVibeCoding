import Foundation

public enum PathInputCommand: Equatable, Sendable {
    case openTerminal(directory: URL)
    case openVSCode(target: URL)
    case openDefault(target: URL)
}
