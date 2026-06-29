import Foundation
import XCTest
@testable import MyMacFinder

final class PathResolverTests: XCTestCase {
    func testExpandsTildeToHomeDirectory() throws {
        let resolver = PathResolver(aliases: [:])

        let resolved = try resolver.resolve("~/Downloads", relativeTo: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(resolved.path, FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path)
    }

    func testResolvesAliasWithRemainingPath() throws {
        let devURL = URL(fileURLWithPath: "/Users/example/personalDev", isDirectory: true)
        let resolver = PathResolver(aliases: ["@dev": devURL])

        let resolved = try resolver.resolve("@dev/app", relativeTo: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(resolved.path, "/Users/example/personalDev/app")
    }

    func testResolvesAbsolutePath() throws {
        let resolver = PathResolver(aliases: [:])

        let resolved = try resolver.resolve("/Applications", relativeTo: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(resolved.path, "/Applications")
    }

    func testResolvesRelativePathAgainstCurrentFolder() throws {
        let resolver = PathResolver(aliases: [:])
        let current = URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true)

        let resolved = try resolver.resolve("project-a", relativeTo: current)

        XCTAssertEqual(resolved.path, "/Users/example/Desktop/project-a")
    }

    func testRejectsEmptyPath() {
        let resolver = PathResolver(aliases: [:])

        XCTAssertThrowsError(try resolver.resolve("   ", relativeTo: URL(fileURLWithPath: "/tmp"))) { error in
            XCTAssertEqual(error as? ExplorerError, .invalidPath(""))
        }
    }
}
