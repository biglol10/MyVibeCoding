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

    func testStaleBookmarkRefreshFailureStopsStartedSecurityScopedAccess() {
        let url = URL(fileURLWithPath: "/tmp/stale-grant", isDirectory: true)
        var stoppedURLs: [URL] = []

        XCTAssertThrowsError(
            try SecurityScopedBookmarkResolver.resolveAccess(
                url: url,
                isStale: true,
                startAccessing: { _ in true },
                refreshBookmarkData: { _ in throw StubBookmarkResolverError.refreshFailed },
                stopAccessing: { stoppedURLs.append($0.standardizedFileURL) }
            )
        )

        XCTAssertEqual(stoppedURLs, [url.standardizedFileURL])
    }

    func testStaleBookmarkRefreshFailureDoesNotStopAccessThatNeverStarted() {
        let url = URL(fileURLWithPath: "/tmp/stale-denied-grant", isDirectory: true)
        var stoppedURLs: [URL] = []

        XCTAssertThrowsError(
            try SecurityScopedBookmarkResolver.resolveAccess(
                url: url,
                isStale: true,
                startAccessing: { _ in false },
                refreshBookmarkData: { _ in throw StubBookmarkResolverError.refreshFailed },
                stopAccessing: { stoppedURLs.append($0.standardizedFileURL) }
            )
        )

        XCTAssertEqual(stoppedURLs, [])
    }

    func testStaleBookmarkRefreshSuccessReturnsFreshDataWithoutStoppingAccess() throws {
        let url = URL(fileURLWithPath: "/tmp/refreshed-grant", isDirectory: true)
        let refreshedData = Data([5, 4, 3])
        var stoppedURLs: [URL] = []

        let access = try SecurityScopedBookmarkResolver.resolveAccess(
            url: url,
            isStale: true,
            startAccessing: { _ in true },
            refreshBookmarkData: { _ in refreshedData },
            stopAccessing: { stoppedURLs.append($0.standardizedFileURL) }
        )

        XCTAssertEqual(access.refreshedBookmarkData, refreshedData)
        XCTAssertTrue(access.didStartAccessing)
        XCTAssertEqual(stoppedURLs, [])
    }

    func testFreshBookmarkDoesNotRegenerateBookmarkData() throws {
        let url = URL(fileURLWithPath: "/tmp/fresh-grant", isDirectory: true)
        var refreshCallCount = 0

        let access = try SecurityScopedBookmarkResolver.resolveAccess(
            url: url,
            isStale: false,
            startAccessing: { _ in true },
            refreshBookmarkData: { _ in
                refreshCallCount += 1
                return Data([1])
            },
            stopAccessing: { _ in }
        )

        XCTAssertNil(access.refreshedBookmarkData)
        XCTAssertEqual(refreshCallCount, 0)
    }
}

private enum StubBookmarkResolverError: Error {
    case refreshFailed
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
