import Darwin
import Foundation

public struct DiskSpaceCandidate: Equatable, Identifiable, Sendable {
    public let title: String
    public let path: String
    public let sizeBytes: UInt64

    public var id: String { path }

    public init(title: String, path: String, sizeBytes: UInt64) {
        self.title = title
        self.path = path
        self.sizeBytes = sizeBytes
    }
}

public struct DiskSpaceCandidateTarget: Equatable, Sendable {
    public let title: String
    public let url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

public struct DiskSpaceCandidateScanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(targets: [DiskSpaceCandidateTarget]? = nil) -> [DiskSpaceCandidate] {
        let scanTargets = targets ?? defaultTargets()
        return scanTargets.compactMap { target in
            guard fileManager.fileExists(atPath: target.url.path) else { return nil }
            let size = folderSize(at: target.url)
            guard size > 0 else { return nil }
            return DiskSpaceCandidate(title: target.title, path: target.url.path, sizeBytes: size)
        }
        .sorted {
            $0.sizeBytes == $1.sizeBytes
                ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                : $0.sizeBytes > $1.sizeBytes
        }
    }

    private func folderSize(at url: URL) -> UInt64 {
        if let size = duSize(at: url) {
            return size
        }

        return limitedFolderSize(at: url)
    }

    private func duSize(at url: URL, timeout: TimeInterval = 1.5) -> UInt64? {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", url.path]
        process.standardOutput = output
        process.standardError = error

        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        guard !process.isRunning else {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            return nil
        }

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0,
              let outputText = String(data: outputData, encoding: .utf8),
              let firstField = outputText.split(whereSeparator: \.isWhitespace).first,
              let kibibytes = UInt64(firstField)
        else {
            _ = error.fileHandleForReading.readDataToEndOfFile()
            return nil
        }

        return kibibytes * 1_024
    }

    private func limitedFolderSize(at url: URL, maxFiles: Int = 2_000) -> UInt64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return 0
        }

        var total: UInt64 = 0
        var scannedFiles = 0
        for case let fileURL as URL in enumerator {
            guard scannedFiles < maxFiles else { break }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize
            else {
                continue
            }
            total += UInt64(fileSize)
            scannedFiles += 1
        }
        return total
    }

    private func defaultTargets() -> [DiskSpaceCandidateTarget] {
        let home = fileManager.homeDirectoryForCurrentUser
        return [
            DiskSpaceCandidateTarget(title: "Downloads", url: home.appendingPathComponent("Downloads", isDirectory: true)),
            DiskSpaceCandidateTarget(title: "Trash", url: home.appendingPathComponent(".Trash", isDirectory: true)),
            DiskSpaceCandidateTarget(title: "Caches", url: home.appendingPathComponent("Library/Caches", isDirectory: true)),
            DiskSpaceCandidateTarget(title: "Xcode DerivedData", url: home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true))
        ]
    }
}
