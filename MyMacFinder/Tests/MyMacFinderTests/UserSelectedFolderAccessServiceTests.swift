import Foundation
import XCTest
@testable import MyMacFinder

final class UserSelectedFolderAccessServiceTests: XCTestCase {
    func testPickerCancellationReturnsCancelledResult() async throws {
        let picker = StubFolderPicker(result: nil)
        let service = UserSelectedFolderAccessService(
            picker: picker,
            bookmarkResolver: StubBookmarkResolver()
        )

        let result = try await service.chooseFolder(startingAt: nil, sandboxed: true)

        XCTAssertEqual(result, .cancelled)
    }

    func testSandboxedSelectionCreatesBookmarkGrantAndStartsAccess() async throws {
        let url = URL(fileURLWithPath: "/tmp/granted", isDirectory: true)
        let resolver = StubBookmarkResolver(bookmarkData: Data([4, 5, 6]))
        let service = UserSelectedFolderAccessService(
            picker: StubFolderPicker(result: url),
            bookmarkResolver: resolver
        )

        let result = try await service.chooseFolder(startingAt: nil, sandboxed: true)

        guard case .granted(let grant, let access) = result else {
            return XCTFail("Expected granted result")
        }
        XCTAssertEqual(grant.url, url.standardizedFileURL)
        XCTAssertEqual(grant.bookmarkData, Data([4, 5, 6]))
        XCTAssertEqual(access.url, url.standardizedFileURL)
        XCTAssertEqual(resolver.startedURLs, [url.standardizedFileURL])
    }

    func testUnrestrictedSelectionReturnsGrantWithoutBookmarkData() async throws {
        let url = URL(fileURLWithPath: "/tmp/unrestricted", isDirectory: true)
        let service = UserSelectedFolderAccessService(
            picker: StubFolderPicker(result: url),
            bookmarkResolver: StubBookmarkResolver()
        )

        let result = try await service.chooseFolder(startingAt: nil, sandboxed: false)

        guard case .granted(let grant, _) = result else {
            return XCTFail("Expected granted result")
        }
        XCTAssertEqual(grant.url, url.standardizedFileURL)
        XCTAssertEqual(grant.bookmarkData, Data())
    }
}

private final class StubFolderPicker: FolderPicking, @unchecked Sendable {
    var result: URL?

    init(result: URL?) {
        self.result = result
    }

    @MainActor
    func chooseFolder(startingAt url: URL?) async -> URL? {
        result
    }
}

private final class StubBookmarkResolver: BookmarkResolving, @unchecked Sendable {
    var bookmarkData: Data
    var startedURLs: [URL] = []

    init(bookmarkData: Data = Data([1])) {
        self.bookmarkData = bookmarkData
    }

    func bookmarkData(for url: URL, sandboxed: Bool) throws -> Data {
        sandboxed ? bookmarkData : Data()
    }

    func resolve(_ grant: FolderAccessGrant) throws -> ResolvedFolderAccess {
        ResolvedFolderAccess(url: grant.url, isStale: false, didStartAccessing: true)
    }

    func startAccessing(_ url: URL, sandboxed: Bool) -> ResolvedFolderAccess {
        startedURLs.append(url.standardizedFileURL)
        return ResolvedFolderAccess(url: url.standardizedFileURL, isStale: false, didStartAccessing: sandboxed)
    }

    func stopAccessing(_ access: ResolvedFolderAccess) {}
}
