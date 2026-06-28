import Foundation

public enum BrowserURLDomain {
    public static func extract(from rawURL: String) -> String? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased()
        else {
            return nil
        }

        let normalized = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .removingWwwPrefix
        return normalized.isEmpty ? nil : normalized
    }
}

private extension String {
    var removingWwwPrefix: String {
        hasPrefix("www.") ? String(dropFirst(4)) : self
    }
}
