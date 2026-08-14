import Foundation

public struct SearchQuery: Equatable, Sendable {
    public var freeTerms: [String]
    public var nameTerms: [String]
    public var pathTerms: [String]
    public var extensions: [String]
    public var kinds: [IndexedFileKind]
    public var modifiedRange: Range<Date>?
    public var sizeRange: ByteSizeRange?

    public init(
        freeTerms: [String] = [],
        nameTerms: [String] = [],
        pathTerms: [String] = [],
        extensions: [String] = [],
        kinds: [IndexedFileKind] = [],
        modifiedRange: Range<Date>? = nil,
        sizeRange: ByteSizeRange? = nil
    ) {
        self.freeTerms = freeTerms
        self.nameTerms = nameTerms
        self.pathTerms = pathTerms
        self.extensions = extensions
        self.kinds = kinds
        self.modifiedRange = modifiedRange
        self.sizeRange = sizeRange
    }

    public var isEmpty: Bool {
        freeTerms.isEmpty
            && nameTerms.isEmpty
            && pathTerms.isEmpty
            && extensions.isEmpty
            && kinds.isEmpty
            && modifiedRange == nil
            && sizeRange == nil
    }
}

public enum SearchQueryParseError: Error, Equatable, LocalizedError, Sendable {
    case unknownFilter(String)
    case missingValue(String)
    case unterminatedQuote
    case unsupportedKind(String)
    case invalidModified(String)
    case invalidSize(String)

    public var errorDescription: String? {
        switch self {
        case .unknownFilter(let filter):
            return "Unknown search filter: \(filter)"
        case .missingValue(let filter):
            return "Search filter requires a value: \(filter)"
        case .unterminatedQuote:
            return "A quoted search value is not closed."
        case .unsupportedKind(let kind):
            return "Unsupported file kind: \(kind)"
        case .invalidModified(let value):
            return "Unsupported modified date: \(value)"
        case .invalidSize(let value):
            return "Unsupported file size: \(value). Use values such as >100MB or 10MB..1GB."
        }
    }
}
