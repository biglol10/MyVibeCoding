import Foundation
import XCTest
@testable import MyMacFinder

final class PathInputCommandResolverTests: XCTestCase {
    func testCmdOpensTerminalAtCurrentDirectory() {
        let currentURL = URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true)
        let resolver = PathInputCommandResolver(pathResolver: PathResolver(aliases: [:]))

        XCTAssertEqual(
            resolver.command(for: "cmd", currentURL: currentURL),
            .openTerminal(directory: currentURL.standardizedFileURL)
        )
    }

    func testTerminalOpensTerminalAtCurrentDirectory() {
        let currentURL = URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true)
        let resolver = PathInputCommandResolver(pathResolver: PathResolver(aliases: [:]))

        XCTAssertEqual(
            resolver.command(for: "terminal", currentURL: currentURL),
            .openTerminal(directory: currentURL.standardizedFileURL)
        )
    }

    func testCodeDotOpensCurrentDirectoryInVSCode() {
        let currentURL = URL(fileURLWithPath: "/Users/example/Projects", isDirectory: true)
        let resolver = PathInputCommandResolver(pathResolver: PathResolver(aliases: [:]))

        XCTAssertEqual(
            resolver.command(for: "code .", currentURL: currentURL),
            .openVSCode(target: currentURL.standardizedFileURL)
        )
    }

    func testCodeResolvesQuotedRelativePath() {
        let currentURL = URL(fileURLWithPath: "/Users/example/Projects", isDirectory: true)
        let resolver = PathInputCommandResolver(pathResolver: PathResolver(aliases: [:]))

        XCTAssertEqual(
            resolver.command(for: "code \"My Project\"", currentURL: currentURL),
            .openVSCode(target: currentURL.appendingPathComponent("My Project").standardizedFileURL)
        )
    }

    func testOpenDotUsesDefaultMacOSOpenBehavior() {
        let currentURL = URL(fileURLWithPath: "/Users/example/Downloads", isDirectory: true)
        let resolver = PathInputCommandResolver(pathResolver: PathResolver(aliases: [:]))

        XCTAssertEqual(
            resolver.command(for: "open .", currentURL: currentURL),
            .openDefault(target: currentURL.standardizedFileURL)
        )
    }

    func testUnknownInputIsNotACommand() {
        let currentURL = URL(fileURLWithPath: "/Users/example/Desktop", isDirectory: true)
        let resolver = PathInputCommandResolver(pathResolver: PathResolver(aliases: [:]))

        XCTAssertNil(resolver.command(for: "Documents", currentURL: currentURL))
        XCTAssertNil(resolver.command(for: "rm -rf ~/Documents", currentURL: currentURL))
    }
}
