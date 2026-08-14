import Foundation
import XCTest
@testable import MyMacSearchAppSupport
@testable import MyMacSearchCore

final class ResultActionServiceTests: XCTestCase {
    @MainActor
    func testMissingPathQueuesReconciliationAndFailsClearly() async {
        let environment = ResultActionEnvironmentSpy(status: .missing)
        var reconciled: [String] = []
        let service = ResultActionService(environment: environment) { reconciled.append($0) }
        let entry = IndexedEntry.actionFixture(path: "/scope/gone.txt")

        do {
            try await service.perform(.open, entry: entry)
            XCTFail("Expected missing-path failure")
        } catch let error as ResultActionError {
            XCTAssertEqual(error, .missingPath("/scope/gone.txt"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(reconciled, ["/scope/gone.txt"])
    }

    @MainActor
    func testFileOpensParentDirectoryInTerminal() async throws {
        let environment = ResultActionEnvironmentSpy(status: .file)
        environment.applicationURLs[ResultActionService.terminalBundleIdentifier] = URL(
            fileURLWithPath: "/Applications/Terminal.app"
        )
        let service = ResultActionService(environment: environment)

        try await service.perform(
            .openInTerminal,
            entry: .actionFixture(path: "/scope/folder/report.pdf")
        )

        XCTAssertEqual(environment.launchedURLs.map(\.path), ["/scope/folder"])
        XCTAssertEqual(environment.launchedApplication?.path, "/Applications/Terminal.app")
    }

    @MainActor
    func testIncompatibleMyMacFinderDoesNotReportSuccess() async {
        let environment = ResultActionEnvironmentSpy(status: .file)
        environment.applicationURLs[ResultActionService.myMacFinderBundleIdentifier] = URL(
            fileURLWithPath: "/Applications/MyMacFinder.app"
        )
        environment.capability = false
        let service = ResultActionService(environment: environment)

        do {
            try await service.perform(
                .openInMyMacFinder,
                entry: .actionFixture(path: "/scope/report.pdf")
            )
            XCTFail("Expected incompatible app failure")
        } catch let error as ResultActionError {
            XCTAssertEqual(error, .incompatibleMyMacFinder)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(environment.launchedURLs.isEmpty)
    }
}

@MainActor
private final class ResultActionEnvironmentSpy: ResultActionEnvironment {
    var status: ResultPathStatus
    var applicationURLs: [String: URL] = [:]
    var capability = true
    var launchedURLs: [URL] = []
    var launchedApplication: URL?

    init(status: ResultPathStatus) {
        self.status = status
    }

    func pathStatus(at url: URL) -> ResultPathStatus { status }
    func open(_ url: URL) -> Bool { true }
    func reveal(_ url: URL) -> Bool { true }
    func copyPath(_ path: String) -> Bool { true }
    func applicationURL(bundleIdentifier: String) -> URL? { applicationURLs[bundleIdentifier] }
    func hasCapability(_ key: String, applicationURL: URL) -> Bool { capability }

    func launch(_ urls: [URL], withApplicationAt applicationURL: URL) async throws {
        launchedURLs = urls
        launchedApplication = applicationURL
    }
}

private extension IndexedEntry {
    static func actionFixture(path: String) -> IndexedEntry {
        IndexedEntry(
            scopeID: "scope",
            path: path,
            parentPath: URL(fileURLWithPath: path).deletingLastPathComponent().path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            fileExtension: URL(fileURLWithPath: path).pathExtension,
            kind: .document,
            sizeBytes: 1,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isDirectory: false,
            isSymlink: false,
            isPackage: false,
            isHidden: false,
            scanGeneration: 1
        )
    }
}
