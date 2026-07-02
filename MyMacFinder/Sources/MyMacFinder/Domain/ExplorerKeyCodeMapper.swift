import Foundation

public enum ExplorerKeyCodeMapper {
    public static func key(for keyCode: UInt16, charactersIgnoringModifiers: String?) -> String {
        switch keyCode {
        case 36, 76:
            return "return"
        case 49:
            return "space"
        case 51, 117:
            return "delete"
        case 53:
            return "escape"
        case 48:
            return "tab"
        case 120:
            return "f2"
        case 96:
            return "f5"
        case 97:
            return "f6"
        case 123:
            return "left"
        case 124:
            return "right"
        case 126:
            return "up"
        case 125:
            return "down"
        default:
            return charactersIgnoringModifiers?.lowercased() ?? ""
        }
    }
}
