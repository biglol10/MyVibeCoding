import Foundation

public enum ExplorerKeyCodeMapper {
    public static func key(for keyCode: UInt16, charactersIgnoringModifiers: String?) -> String {
        switch keyCode {
        case 36, 76:
            return "return"
        case 49:
            return "space"
        case 51:
            return "backspace"
        case 117:
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
            let text = charactersIgnoringModifiers?.lowercased() ?? ""
            // Control letters and Korean input can produce non-letter characters in NSEvent.
            if text.unicodeScalars.contains(where: { $0.value < 32 || $0.value > 127 }) {
                let physical: [UInt16: String] = [0:"a",1:"s",2:"d",3:"f",4:"h",5:"g",6:"z",7:"x",8:"c",9:"v",11:"b",12:"q",13:"w",14:"e",15:"r",16:"y",17:"t",31:"o",32:"u",34:"i",35:"p",37:"l",38:"j",40:"k",45:"n",46:"m",47:"."]
                if let letter = physical[keyCode] { return letter }
            }
            return text
        }
    }
}
