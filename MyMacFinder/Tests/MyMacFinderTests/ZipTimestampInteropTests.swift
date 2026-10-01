import Foundation
import XCTest
@testable import MyMacFinder

final class ZipTimestampInteropTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZipTimestampInterop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    @MainActor
    func testBrowsingDOSOnlyZipUsesLocalCalendarTime() async throws {
        let zip = try makeIndependentZip()
        let entries = try await ArchiveBrowsingService().list(
            ArchiveLocation(archiveURL: zip, internalPath: ""), showHiddenFiles: false
        )
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(try XCTUnwrap(entry.modifiedAt).timeIntervalSince1970,
                       localFixtureDate.timeIntervalSince1970, accuracy: 1)
    }

    @MainActor
    func testExtractedTimestampMatchesMacOSDittoForDOSOnlyZip() async throws {
        let zip = try makeIndependentZip()
        let appDestination = root.appendingPathComponent("app", isDirectory: true)
        let nativeDestination = root.appendingPathComponent("ditto", isDirectory: true)
        try FileManager.default.createDirectory(at: appDestination, withIntermediateDirectories: false)
        let result = try await ZipExtractionService().extract([zip], to: appDestination)
        _ = try run("/usr/bin/ditto", ["-x", "-k", zip.path, nativeDestination.path])
        let extracted = try XCTUnwrap(result.createdURLs.first).appendingPathComponent("timestamp.txt")
        let native = nativeDestination.appendingPathComponent("timestamp.txt")
        let appDate = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: extracted.path)[.modificationDate] as? Date)
        let nativeDate = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: native.path)[.modificationDate] as? Date)
        XCTAssertEqual(appDate.timeIntervalSince1970, nativeDate.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(try Data(contentsOf: extracted), try Data(contentsOf: native))
    }

    @MainActor
    func testCompressionWritesLocalDOSTimeThatPythonAndDittoReadCorrectly() async throws {
        let source = root.appendingPathComponent("source.txt")
        try Data("timestamp contents".utf8).write(to: source)
        try FileManager.default.setAttributes([.modificationDate: localFixtureDate], ofItemAtPath: source.path)
        let result = try await ZipCompressionService().compress([source], to: root)
        let zip = try XCTUnwrap(result.createdURLs.first)
        let header = try run("/usr/bin/env", ["python3", "-c", "import zipfile,sys; print(','.join(map(str,zipfile.ZipFile(sys.argv[1]).infolist()[0].date_time)))", zip.path])
        XCTAssertEqual(header.trimmingCharacters(in: .whitespacesAndNewlines), "2026,9,30,23,24,20")
        let destination = root.appendingPathComponent("native read", isDirectory: true)
        _ = try run("/usr/bin/ditto", ["-x", "-k", zip.path, destination.path])
        let file = destination.appendingPathComponent(source.lastPathComponent)
        let date = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
        XCTAssertEqual(date.timeIntervalSince1970, localFixtureDate.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(try Data(contentsOf: file), try Data(contentsOf: source))
    }

    private var localFixtureDate: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 23, minute: 24, second: 20))!
    }

    private func makeIndependentZip() throws -> URL {
        let zip = root.appendingPathComponent("independent.zip")
        _ = try run("/usr/bin/env", ["python3", "-c", "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],'w'); i=zipfile.ZipInfo('timestamp.txt',(2026,9,30,23,24,20)); z.writestr(i,b'timestamp contents'); z.close()", zip.path])
        return zip
    }

    private func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ExplorerError.operationFailed(String(decoding: data, as: UTF8.self))
        }
        return String(decoding: data, as: UTF8.self)
    }
}
