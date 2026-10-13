import Foundation

public enum SMBServerAddress {
    public static func parse(_ value: String) throws -> URL {
        let address = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = address.contains("://") ? address : "smb://" + address
        guard let components = URLComponents(string: text), components.scheme?.lowercased() == "smb",
              let host = components.host, !host.isEmpty, !host.contains(where: \.isWhitespace),
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port == nil || (1...65535).contains(components.port!),
              let url = components.url else {
            throw ExplorerError.invalidPath("Enter smb://server/share without credentials. macOS handles login securely.")
        }
        return url
    }
}
