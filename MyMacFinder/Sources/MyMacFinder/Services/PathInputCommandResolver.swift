import Foundation

public struct PathInputCommandResolver: Sendable {
    private let pathResolver: PathResolver

    public init(pathResolver: PathResolver) {
        self.pathResolver = pathResolver
    }

    public func command(for rawInput: String, currentURL: URL) -> PathInputCommand? {
        guard let tokens = Self.tokenize(rawInput), let command = tokens.first?.lowercased() else {
            return nil
        }

        switch command {
        case "cmd", "terminal":
            guard tokens.count == 1 else {
                return nil
            }
            return .openTerminal(directory: currentURL.standardizedFileURL)
        case "code":
            guard tokens.count <= 2 else {
                return nil
            }
            let target = tokens.count == 1 ? currentURL.standardizedFileURL : resolveTarget(tokens[1], currentURL: currentURL)
            return target.map { .openVSCode(target: $0) }
        case "open":
            guard tokens.count == 2, let target = resolveTarget(tokens[1], currentURL: currentURL) else {
                return nil
            }
            return .openDefault(target: target)
        default:
            return nil
        }
    }

    private func resolveTarget(_ rawTarget: String, currentURL: URL) -> URL? {
        try? pathResolver.resolve(rawTarget, relativeTo: currentURL).standardizedFileURL
    }

    private static func tokenize(_ input: String) -> [String]? {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var isEscaped = false

        for character in input.trimmingCharacters(in: .whitespacesAndNewlines) {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                } else {
                    current.append(character)
                }
                continue
            }

            if character.isWhitespace, quote == nil {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                continue
            }

            current.append(character)
        }

        guard quote == nil else {
            return nil
        }

        if isEscaped {
            current.append("\\")
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens.isEmpty ? nil : tokens
    }
}
