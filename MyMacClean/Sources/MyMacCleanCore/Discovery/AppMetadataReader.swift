import Foundation

public enum AppMetadataReaderError: Error, Equatable {
    case missingInfoPlist(URL)
    case unreadableInfoPlist(URL)
}

public struct AppMetadataReader: Sendable {
    private let sizeCalculator: FileSizeCalculator

    public init(sizeCalculator: FileSizeCalculator = FileSizeCalculator()) {
        self.sizeCalculator = sizeCalculator
    }

    public func readApp(at appURL: URL) throws -> InstalledApp {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard FileManager.default.fileExists(atPath: infoURL.path) else {
            throw AppMetadataReaderError.missingInfoPlist(infoURL)
        }
        let data = try Data(contentsOf: infoURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw AppMetadataReaderError.unreadableInfoPlist(infoURL)
        }

        let fallbackName = appURL.deletingPathExtension().lastPathComponent
        let displayName = plist["CFBundleDisplayName"] as? String
            ?? plist["CFBundleName"] as? String
            ?? fallbackName

        return InstalledApp(
            displayName: displayName,
            bundleIdentifier: plist["CFBundleIdentifier"] as? String,
            version: plist["CFBundleShortVersionString"] as? String,
            executableName: plist["CFBundleExecutable"] as? String,
            bundleURL: appURL,
            iconIdentifier: plist["CFBundleIconFile"] as? String,
            bundleSize: try sizeCalculator.sizeOfItem(at: appURL),
            lastOpenedAt: try appURL.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate
        )
    }
}
