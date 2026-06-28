import XCTest
@testable import FlowPilotNativeCore

final class BrowserURLDomainTests: XCTestCase {
    func testExtractsCanonicalDomainFromHTTPSURL() {
        XCTAssertEqual(
            BrowserURLDomain.extract(from: "https://www.Example.COM/docs?q=1"),
            "example.com"
        )
    }

    func testExtractsCanonicalDomainFromHTTPURL() {
        XCTAssertEqual(
            BrowserURLDomain.extract(from: "http://news.ycombinator.com/item?id=1"),
            "news.ycombinator.com"
        )
    }

    func testRejectsNonWebURLs() {
        XCTAssertNil(BrowserURLDomain.extract(from: "file:///Users/example/report.html"))
    }
}
