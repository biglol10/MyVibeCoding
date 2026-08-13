import Foundation

public enum BrowserBridgeParseResult: Equatable {
    case accepted(BrowserEventDraft)
    case incomplete
    case badRequest
    case forbidden
    case methodNotAllowed
    case notFound
    case payloadTooLarge
}

public enum BrowserBridgeHTTPStatus: Int, Equatable {
    case noContent = 204
    case badRequest = 400
    case forbidden = 403
    case notFound = 404
    case methodNotAllowed = 405
    case payloadTooLarge = 413
    case internalServerError = 500
}

public enum BrowserBridgeRequestParser {
    public static let maximumHeaderBytes = 4 * 1024
    public static let maximumBodyBytes = 16 * 1024
    public static let maximumRequestBytes = maximumHeaderBytes + maximumBodyBytes

    private static let headerDelimiter = Data([0x0D, 0x0A, 0x0D, 0x0A])
    private static let requiredBridgeValue = "flowpilot-browser-bridge-v1"

    private enum UTF8Validation {
        case valid
        case incomplete
        case invalid
    }

    public static func parse(_ data: Data, isComplete: Bool) -> BrowserBridgeParseResult {
        guard data.count <= maximumRequestBytes else {
            return .payloadTooLarge
        }

        guard let delimiterRange = data.range(of: headerDelimiter) else {
            guard data.count < maximumHeaderBytes else {
                return .payloadTooLarge
            }

            guard delimiterCanStillFit(in: data) else {
                return .payloadTooLarge
            }

            let utf8Validation = validateUTF8(data)
            guard utf8Validation != .invalid else {
                return .badRequest
            }
            let partialHeader = String(decoding: data, as: UTF8.self)
            if let terminalResult = terminalResultForPartialHeaders(partialHeader) {
                return terminalResult
            }
            return isComplete ? .badRequest : .incomplete
        }

        let headerByteCount = data.distance(from: data.startIndex, to: delimiterRange.upperBound)
        guard headerByteCount <= maximumHeaderBytes else {
            return .payloadTooLarge
        }

        let body = data[delimiterRange.upperBound...]
        guard body.count <= maximumBodyBytes else {
            return .payloadTooLarge
        }

        guard let headerText = String(data: data[..<delimiterRange.lowerBound], encoding: .utf8),
              let (requestLine, headers) = parseHeaders(headerText) else {
            return .badRequest
        }

        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count == 3, requestParts[2] == "HTTP/1.1" else {
            return .badRequest
        }
        guard requestParts[0] == "POST" else {
            return .methodNotAllowed
        }
        guard requestParts[1] == "/browser-event" else {
            return .notFound
        }

        guard let contentLength = validContentLength(headers["content-length"]) else {
            return .badRequest
        }
        guard contentLength <= maximumBodyBytes else {
            return .payloadTooLarge
        }

        guard hasRequiredAuthorization(headers) else {
            return .forbidden
        }

        if body.count < contentLength {
            return isComplete ? .badRequest : .incomplete
        }
        guard body.count == contentLength else {
            return .badRequest
        }

        guard let draft = try? JSONDecoder().decode(BrowserEventDraft.self, from: Data(body)) else {
            return .badRequest
        }
        return .accepted(draft)
    }

    private static func parseHeaders(_ headerText: String) -> (String, [String: String])? {
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.contains("\r"), !line.contains("\n") else {
                return nil
            }
            guard let separator = line.firstIndex(of: ":") else {
                return nil
            }

            let rawName = line[..<separator]
            guard let name = normalizedHeaderName(rawName), headers[name] == nil else {
                return nil
            }

            let valueStart = line.index(after: separator)
            let value = line[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }
        return (requestLine, headers)
    }

    private static func terminalResultForPartialHeaders(_ text: String) -> BrowserBridgeParseResult? {
        guard let requestLineEnd = text.range(of: "\r\n") else {
            return terminalResultForPartialRequestLine(text)
        }

        let requestLine = String(text[..<requestLineEnd.lowerBound])
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count == 3, requestParts[2] == "HTTP/1.1" else {
            return .badRequest
        }
        guard requestParts[0] == "POST" else {
            return .methodNotAllowed
        }
        guard requestParts[1] == "/browser-event" else {
            return .notFound
        }

        let headerPrefix = String(text[requestLineEnd.upperBound...])
        return isPotentiallyValidHeaderPrefix(headerPrefix) ? nil : .badRequest
    }

    private static func terminalResultForPartialRequestLine(_ text: String) -> BrowserBridgeParseResult? {
        let expectedRequestLine = "POST /browser-event HTTP/1.1"
        if text == expectedRequestLine + "\r" {
            return nil
        }
        guard !expectedRequestLine.hasPrefix(text) else {
            return nil
        }

        guard text.hasPrefix("POST ") else {
            return .methodNotAllowed
        }

        let targetStart = text.index(text.startIndex, offsetBy: "POST ".count)
        let targetAndVersion = text[targetStart...]
        let target = targetAndVersion.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).first
        guard target == "/browser-event" else {
            return .notFound
        }
        return .badRequest
    }

    private static func isPotentiallyValidHeaderPrefix(_ prefix: String) -> Bool {
        var completePrefix = prefix
        if completePrefix.hasSuffix("\r") {
            completePrefix.removeLast()
        }

        let headerTextWithoutValidLineEndings = completePrefix.replacingOccurrences(of: "\r\n", with: "")
        guard !headerTextWithoutValidLineEndings.contains("\r"),
              !headerTextWithoutValidLineEndings.contains("\n") else {
            return false
        }

        let parts = completePrefix.components(separatedBy: "\r\n")
        let hasCompleteFinalHeader = completePrefix.hasSuffix("\r\n")
        let completeLines = parts.dropLast()
        let partialLine = hasCompleteFinalHeader ? "" : (parts.last ?? "")

        var headerNames: Set<String> = []
        for line in completeLines {
            guard let name = headerName(in: line), headerNames.insert(name).inserted else {
                return false
            }
        }
        guard !partialLine.contains("\r"), !partialLine.contains("\n") else {
            return false
        }
        guard let separator = partialLine.firstIndex(of: ":") else {
            return true
        }
        guard let name = normalizedHeaderName(partialLine[..<separator]) else {
            return false
        }
        return !headerNames.contains(name)
    }

    private static func headerName(in line: String) -> String? {
        guard let separator = line.firstIndex(of: ":") else {
            return nil
        }
        return normalizedHeaderName(line[..<separator])
    }

    private static func normalizedHeaderName(_ rawName: Substring) -> String? {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, String(rawName) == trimmedName else {
            return nil
        }
        return trimmedName.lowercased()
    }

    private static func delimiterCanStillFit(in data: Data) -> Bool {
        let remainingHeaderBytes = maximumHeaderBytes - data.count
        let delimiterPrefixLength = longestDelimiterPrefixAtEnd(of: data)
        return headerDelimiter.count - delimiterPrefixLength <= remainingHeaderBytes
    }

    private static func longestDelimiterPrefixAtEnd(of data: Data) -> Int {
        let maximumPrefixLength = min(headerDelimiter.count - 1, data.count)
        guard maximumPrefixLength > 0 else {
            return 0
        }

        for length in stride(from: maximumPrefixLength, through: 1, by: -1) {
            let dataSuffix = data.suffix(length)
            let delimiterPrefix = headerDelimiter.prefix(length)
            if dataSuffix.elementsEqual(delimiterPrefix) {
                return length
            }
        }
        return 0
    }

    private static func validateUTF8(_ data: Data) -> UTF8Validation {
        let bytes = [UInt8](data)
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]
            if byte <= 0x7F {
                index += 1
                continue
            }

            let continuationRanges: [ClosedRange<UInt8>]
            switch byte {
            case 0xC2...0xDF:
                continuationRanges = [0x80...0xBF]
            case 0xE0:
                continuationRanges = [0xA0...0xBF, 0x80...0xBF]
            case 0xE1...0xEC, 0xEE...0xEF:
                continuationRanges = [0x80...0xBF, 0x80...0xBF]
            case 0xED:
                continuationRanges = [0x80...0x9F, 0x80...0xBF]
            case 0xF0:
                continuationRanges = [0x90...0xBF, 0x80...0xBF, 0x80...0xBF]
            case 0xF1...0xF3:
                continuationRanges = [0x80...0xBF, 0x80...0xBF, 0x80...0xBF]
            case 0xF4:
                continuationRanges = [0x80...0x8F, 0x80...0xBF, 0x80...0xBF]
            default:
                return .invalid
            }

            for (offset, range) in continuationRanges.enumerated() {
                let continuationIndex = index + offset + 1
                guard continuationIndex < bytes.count else {
                    return .incomplete
                }
                guard range.contains(bytes[continuationIndex]) else {
                    return .invalid
                }
            }
            index += continuationRanges.count + 1
        }
        return .valid
    }

    private static func validContentLength(_ value: String?) -> Int? {
        guard let value, !value.isEmpty,
              value.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else {
            return nil
        }
        return Int(value)
    }

    private static func hasRequiredAuthorization(_ headers: [String: String]) -> Bool {
        guard headers["x-flowpilot-bridge"] == requiredBridgeValue,
              let contentType = headers["content-type"] else {
            return false
        }

        let mediaType = contentType
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return mediaType == "application/json"
    }
}

public enum BrowserBridgeResponsePolicy {
    public static func status(
        parseResult: BrowserBridgeParseResult,
        persistenceSucceeded: Bool? = nil
    ) -> BrowserBridgeHTTPStatus? {
        switch parseResult {
        case .accepted:
            guard let persistenceSucceeded else { return nil }
            return persistenceSucceeded ? .noContent : .internalServerError
        case .incomplete:
            return nil
        case .badRequest:
            return .badRequest
        case .forbidden:
            return .forbidden
        case .methodNotAllowed:
            return .methodNotAllowed
        case .notFound:
            return .notFound
        case .payloadTooLarge:
            return .payloadTooLarge
        }
    }
}
