import Foundation

public enum FullDiskAccessStatus: Equatable, Sendable {
    case granted
    case missing
    case undetermined
}

public struct FullDiskAccessPromptPresentation: Equatable, Sendable {
    public let appName: String

    public init(appName: String = "MyMacClean") {
        self.appName = appName
    }

    public var title: String {
        "Full Disk Access Required"
    }

    public var message: String {
        "\(appName) needs Full Disk Access to scan and delete app support files in protected Library locations. Enable \(appName) in System Settings, then restart the app."
    }

    public var settingsURL: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    }

    public var primaryButtonTitle: String {
        "Open System Settings"
    }
}

public struct FullDiskAccessProbe: Sendable {
    public typealias DirectoryContentsProvider = @Sendable (URL) throws -> [URL]

    private let protectedURLs: [URL]
    private let directoryContents: DirectoryContentsProvider

    public init(
        protectedURLs: [URL] = FullDiskAccessProbe.defaultProtectedURLs(),
        directoryContents: @escaping DirectoryContentsProvider = { url in
            try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        }
    ) {
        self.protectedURLs = protectedURLs
        self.directoryContents = directoryContents
    }

    public func status() -> FullDiskAccessStatus {
        for url in protectedURLs {
            do {
                _ = try directoryContents(url)
                return .granted
            } catch {
                switch permissionStatus(for: error) {
                case .missing:
                    return .missing
                case .undetermined:
                    continue
                case .granted:
                    return .granted
                }
            }
        }

        return .undetermined
    }

    private func permissionStatus(for error: Error) -> FullDiskAccessStatus {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            if [CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue].contains(nsError.code) {
                return .missing
            }
            if nsError.code == CocoaError.fileNoSuchFile.rawValue {
                return .undetermined
            }
        }
        if nsError.domain == NSPOSIXErrorDomain {
            if nsError.code == Int(EACCES) || nsError.code == Int(EPERM) {
                return .missing
            }
            if nsError.code == Int(ENOENT) {
                return .undetermined
            }
        }
        return .undetermined
    }

    public static func defaultProtectedURLs(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            homeDirectory.appendingPathComponent("Library/Mail", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Messages", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Safari", isDirectory: true)
        ]
    }
}
