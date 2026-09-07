import Foundation
import CryptoKit

public enum DocumentError: LocalizedError, Equatable, Sendable {
    case unsupportedEncoding, conflict, deleted, unsafePath, invalidChange, unavailable
    public var errorDescription: String? {
        switch self {
        case .unsupportedEncoding: "UTF-8 문서만 편집할 수 있습니다. 원본 파일은 변경하지 않았습니다."
        case .conflict: "다른 프로그램에서 파일을 변경했습니다. 자동 저장을 멈췄습니다."
        case .deleted: "파일이 이동되거나 삭제되었습니다. 편집본을 다른 이름으로 저장할 수 있습니다."
        case .unsafePath: "이 경로에는 안전하게 접근할 수 없습니다. 실제 파일이나 폴더를 선택해 주세요."
        case .invalidChange: "편집 상태를 동기화하지 못했습니다. 복구본을 보존하고 저장을 멈췄습니다."
        case .unavailable: "파일을 읽을 수 없습니다. 동기화 상태와 접근 권한을 확인해 주세요."
        }
    }
}

public struct DocumentCodec: Codable, Sendable {
    public let originalData: Data
    public let originalText: String
    public let hasBOM: Bool
    public let lineEnding: String

    public init(data: Data) throws {
        hasBOM = data.starts(with: [0xEF, 0xBB, 0xBF])
        let body = hasBOM ? data.dropFirst(3) : data[...]
        guard let source = String(data: body, encoding: .utf8), !source.contains("\0") else {
            throw DocumentError.unsupportedEncoding
        }
        originalData = data
        lineEnding = source.contains("\r\n") ? "\r\n" : (source.contains("\r") ? "\r" : "\n")
        originalText = Self.normalize(source)
    }

    public static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    public func encode(_ text: String) -> Data {
        if text == originalText { return originalData }
        // Retain the exact terminator of unchanged lines, including mixed CRLF/LF files.
        let original = String(data: hasBOM ? originalData.dropFirst(3) : originalData[...], encoding: .utf8) ?? ""
        let oldLines = Self.linesWithEndings(original)
        let newLines = text.components(separatedBy: "\n")
        let oldBodies = oldLines.map(\.0)
        let difference = newLines.difference(from: oldBodies)
        var endings = oldLines.map(\.1)
        for change in difference {
            switch change {
            case .remove(let offset, _, _): endings.remove(at: offset)
            case .insert(let offset, _, _): endings.insert(lineEnding, at: offset)
            }
        }
        let body = newLines.enumerated().map { i, line in
            line + (i == newLines.count - 1 ? "" : (endings[i].isEmpty ? lineEnding : endings[i]))
        }.joined()
        var bytes = hasBOM ? Data([0xEF, 0xBB, 0xBF]) : Data()
        bytes.append(Data(body.utf8))
        return bytes
    }

    private static func linesWithEndings(_ text: String) -> [(String, String)] {
        let ns = text as NSString
        let regex = try! NSRegularExpression(pattern: "\\r\\n|\\r|\\n")
        var result: [(String, String)] = []
        var start = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result.append((ns.substring(with: NSRange(location: start, length: match.range.location - start)), ns.substring(with: match.range)))
            start = NSMaxRange(match.range)
        }
        result.append((ns.substring(from: start), ""))
        return result
    }

    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct TextChange: Codable, Sendable {
    public let from: Int
    public let to: Int
    public let insert: String
    public init(from: Int, to: Int, insert: String) { self.from = from; self.to = to; self.insert = insert }

    public static func apply(_ changes: [TextChange], to text: String) throws -> String {
        let source = text as NSString
        var end = 0
        for c in changes {
            guard c.from >= end, c.to >= c.from, c.to <= source.length else { throw DocumentError.invalidChange }
            // Reject offsets splitting a UTF-16 surrogate pair.
            for offset in [c.from, c.to] where offset > 0 && offset < source.length {
                let unit = source.character(at: offset)
                guard !(0xDC00...0xDFFF).contains(unit) else { throw DocumentError.invalidChange }
            }
            end = c.to
        }
        let result = NSMutableString(string: text)
        for c in changes.reversed() { result.replaceCharacters(in: NSRange(location: c.from, length: c.to - c.from), with: c.insert) }
        return result as String
    }
}
