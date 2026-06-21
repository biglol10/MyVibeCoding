import Foundation

enum TestFixtures {
    static func temporaryDirectory(named name: String = UUID().uuidString) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyMacCleanTests-\(name)", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    static func makeAppBundle(
        root: URL,
        name: String,
        bundleIdentifier: String,
        version: String = "1.0",
        executableName: String? = nil,
        payloadSize: Int = 3
    ) throws -> URL {
        let appURL = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)

        let executable = executableName ?? name
        let info: [String: Any] = [
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleShortVersionString": version,
            "CFBundleExecutable": executable
        ]
        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: infoURL)

        let executableURL = macOSURL.appendingPathComponent(executable)
        try Data(repeating: 1, count: payloadSize).write(to: executableURL)
        return appURL
    }
}
