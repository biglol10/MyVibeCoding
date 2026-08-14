import Foundation

public enum SearchQueryParser {
    private static let supportedFilters: Set<String> = ["ext", "kind", "path", "name", "modified"]

    public static func parse(
        _ input: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> SearchQuery {
        let tokens = try tokenize(input)
        var result = SearchQuery()

        for token in tokens {
            guard let colon = token.firstIndex(of: ":") else {
                let normalized = SearchTextNormalizer.normalize(token)
                if !normalized.isEmpty {
                    result.freeTerms.append(normalized)
                }
                continue
            }

            let rawFilter = String(token[..<colon])
            let filter = rawFilter.lowercased()
            guard supportedFilters.contains(filter) else {
                throw SearchQueryParseError.unknownFilter(rawFilter)
            }

            let valueStart = token.index(after: colon)
            let rawValue = String(token[valueStart...])
            guard !rawValue.isEmpty else {
                throw SearchQueryParseError.missingValue(filter)
            }

            let value = SearchTextNormalizer.normalize(rawValue)
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
            default:
                preconditionFailure("Every supported filter must be handled")
            }
        }

        return result
    }

    private static func tokenize(_ input: String) throws -> [String] {
        var tokens: [String] = []
        var token = ""
        var isQuoted = false

        for character in input {
            if character == "\"" {
                isQuoted.toggle()
                continue
            }

            if character.isWhitespace && !isQuoted {
                if !token.isEmpty {
                    tokens.append(token)
                    token.removeAll(keepingCapacity: true)
                }
            } else {
                token.append(character)
            }
        }

        guard !isQuoted else {
            throw SearchQueryParseError.unterminatedQuote
        }

        if !token.isEmpty {
            tokens.append(token)
        }
        return tokens
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
