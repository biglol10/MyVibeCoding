import XCTest
@testable import MyMacFinder

final class SMBServerAddressTests: XCTestCase {
    func testBareHostShareGetsSMBSchemeAndWhitespaceIsTrimmed() throws {
        let url = try SMBServerAddress.parse(" server.local/share ")
        XCTAssertEqual(url.host, "server.local")
        XCTAssertEqual(url.scheme, "smb")
        XCTAssertEqual(url.path, "/share")
    }

    func testUnicodeShareAndExplicitPort() throws {
        let url = try SMBServerAddress.parse(" smb://127.0.0.1:1447/한글 공백 ")
        XCTAssertEqual(url.scheme, "smb")
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertEqual(url.port, 1447)
        XCTAssertEqual(url.path, "/한글 공백")
    }

    func testCredentialsQueriesFragmentsAndOtherSchemesAreRejected() {
        for value in ["https://server/share", "smb://user:password@server/share", "smb:///share",
                      "smb://server/share?password=bad", "smb://server/share#fragment",
                      "smb://server:0/share", "smb://server:65536/share", ""] {
            XCTAssertThrowsError(try SMBServerAddress.parse(value), value)
        }
    }
}
