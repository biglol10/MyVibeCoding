import Foundation

public enum SearchQueryParser {
    private static let supportedFilters: Set<String> = ["ext", "kind", "path", "name", "modified", "size"]

    public static func parse(
        _ input: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> SearchQuery {
        try parseDetailed(input, now: now, calendar: calendar).query
    }

    public static func parseDetailed(
        _ input: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> ParsedSearchQuery {
        let tokens = try tokenize(input)
        var result = SearchQuery()
        var detailedTokens: [SearchQueryToken] = []

        for token in tokens {
            guard let colon = token.value.firstIndex(of: ":") else {
                let normalized = SearchTextNormalizer.normalize(token.value)
                if !normalized.isEmpty {
                    result.freeTerms.append(normalized)
                }
                continue
            }

            let rawFilter = String(token.value[..<colon])
            let filter = rawFilter.lowercased()
            guard supportedFilters.contains(filter) else {
                throw SearchQueryParseError.unknownFilter(rawFilter)
            }

            let valueStart = token.value.index(after: colon)
            let rawValue = String(token.value[valueStart...])
            guard !rawValue.isEmpty else {
                throw SearchQueryParseError.missingValue(filter)
            }

            let value = SearchTextNormalizer.normalize(rawValue)
            detailedTokens.append(
                SearchQueryToken(
                    filter: filter,
                    rawText: token.rawText,
                    characterRange: token.characterRange
                )
            )
            switch filter {
            case "ext":
                let extensionValue = value.hasPrefix(".") ? String(value.dropFirst()) : value
                guard !extensionValue.isEmpty else {
                    throw SearchQueryParseError.missingValue(filter)
                }
                result.extensions.append(extensionValue)
            case "kind":
                guard let kind = IndexedFileKind(rawValue: value) else {
                    throw SearchQueryParseError.unsupportedKind(rawValue)
                }
                result.kinds.append(kind)
            case "path":
                result.pathTerms.append(value)
            case "name":
                result.nameTerms.append(value)
            case "modified":
                result.modifiedRange = try modifiedRange(value: value, now: now, calendar: calendar)
            case "size":
                result.sizeRange = try sizeRange(value: rawValue)
            default:
                preconditionFailure("Every supported filter must be handled")
            }
        }

        return ParsedSearchQuery(query: result, tokens: detailedTokens)
    }

    private static func tokenize(_ input: String) throws -> [RawToken] {
        var tokens: [RawToken] = []
        var value = ""
        var rawText = ""
        var start: Int?
        var isQuoted = false

        for (offset, character) in input.enumerated() {
            if character == "\"" {
                if start == nil { start = offset }
                isQuoted.toggle()
                rawText.append(character)
                continue
            }

            if character.isWhitespace && !isQuoted {
                if let tokenStart = start {
                    tokens.append(RawToken(value: value, rawText: rawText, characterRange: tokenStart..<offset))
                    value.removeAll(keepingCapacity: true)
                    rawText.removeAll(keepingCapacity: true)
                    start = nil
                }
            } else {
                if start == nil { start = offset }
                value.append(character)
                rawText.append(character)
            }
        }

        guard !isQuoted else {
            throw SearchQueryParseError.unterminatedQuote
        }

        if let tokenStart = start {
            tokens.append(
                RawToken(
                    value: value,
                    rawText: rawText,
                    characterRange: tokenStart..<input.count
                )
            )
        }
        return tokens
    }

    private struct RawToken {
        let value: String
        let rawText: String
        let characterRange: Range<Int>
    }

    private static func sizeRange(value: String) throws -> ByteSizeRange {
        if let separator = value.range(of: "..") {
            let lowerText = String(value[..<separator.lowerBound])
            let upperText = String(value[separator.upperBound...])
            guard !lowerText.isEmpty, !upperText.isEmpty else {
                throw SearchQueryParseError.invalidSize(value)
            }
            let lower = try byteCount(lowerText, original: value)
            let upper = try byteCount(upperText, original: value)
            guard lower <= upper else { throw SearchQueryParseError.invalidSize(value) }
            return .closed(lower, upper)
        }

        let operation: String
        let quantity: String
        if value.hasPrefix(">=") || value.hasPrefix("<=") {
            operation = String(value.prefix(2))
            quantity = String(value.dropFirst(2))
        } else if value.hasPrefix(">") || value.hasPrefix("<") {
            operation = String(value.prefix(1))
            quantity = String(value.dropFirst())
        } else {
            throw SearchQueryParseError.invalidSize(value)
        }
        let bytes = try byteCount(quantity, original: value)
        switch operation {
        case ">": return .greaterThan(bytes)
        case ">=": return .atLeast(bytes)
        case "<": return .lessThan(bytes)
        case "<=": return .atMost(bytes)
        default: throw SearchQueryParseError.invalidSize(value)
        }
    }

    private static func byteCount(_ text: String, original: String) throws -> Int64 {
        let characters = Array(text.uppercased())
        let digitCount = characters.prefix(while: { $0.isNumber }).count
        guard digitCount > 0, digitCount < characters.count else {
            throw SearchQueryParseError.invalidSize(original)
        }
        let numberText = String(characters[..<digitCount])
        let unit = String(characters[digitCount...])
        guard let number = Int64(numberText), number >= 0 else {
            throw SearchQueryParseError.invalidSize(original)
        }
        let multiplier: Int64
        switch unit {
        case "B": multiplier = 1
        case "KB": multiplier = 1_024
        case "MB": multiplier = 1_048_576
        case "GB": multiplier = 1_073_741_824
        case "TB": multiplier = 1_099_511_627_776
        default: throw SearchQueryParseError.invalidSize(original)
        }
        let multiplied = number.multipliedReportingOverflow(by: multiplier)
        guard !multiplied.overflow else { throw SearchQueryParseError.invalidSize(original) }
        return multiplied.partialValue
    }

    private static func modifiedRange(
        value: String,
        now: Date,
        calendar: Calendar
    ) throws -> Range<Date> {
        if value == "today" {
            let start = calendar.startOfDay(for: now)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                throw SearchQueryParseError.invalidModified(value)
            }
            return start..<end
        }

        guard value.hasSuffix("d"),
              let days = Int(value.dropLast()),
              days > 0,
              let start = calendar.date(byAdding: .day, value: -days, to: now) else {
            throw SearchQueryParseError.invalidModified(value)
        }
        return start..<now
    }
}
