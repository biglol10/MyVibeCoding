import XCTest
@testable import MyMacSearchCore

final class FileKindClassifierTests: XCTestCase {
    func testClassifiesDirectoriesAndPackagesBeforeExtensions() {
        XCTAssertEqual(
            FileKindClassifier.kind(name: "Folder.pdf", isDirectory: true, isPackage: false),
            .folder
        )
        XCTAssertEqual(
            FileKindClassifier.kind(name: "Tool.app", isDirectory: true, isPackage: true),
            .application
        )
    }

    func testClassifiesKnownExtensionsCaseInsensitively() {
        XCTAssertEqual(FileKindClassifier.kind(name: "Guide.PDF", isDirectory: false, isPackage: false), .pdf)
        XCTAssertEqual(FileKindClassifier.kind(name: "Photo.JPEG", isDirectory: false, isPackage: false), .image)
        XCTAssertEqual(FileKindClassifier.kind(name: "Main.SWIFT", isDirectory: false, isPackage: false), .code)
        XCTAssertEqual(FileKindClassifier.kind(name: "Backup.ZIP", isDirectory: false, isPackage: false), .archive)
    }

    func testFallsBackToOther() {
        XCTAssertEqual(FileKindClassifier.kind(name: "unknown.datax", isDirectory: false, isPackage: false), .other)
    }
}
