import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import MyMacFinder

@MainActor
final class FileEntryIconResolverTests: XCTestCase {
    func testFolderUsesFolderContentTypeWithoutReadingItsPath() {
        assertResolvedType(.folder, for: makeEntry(name: "missing-folder", kind: .folder))
    }

    func testPackageUsesApplicationBundleContentTypeWithoutReadingItsPath() {
        assertResolvedType(.applicationBundle, for: makeEntry(name: "Missing.app", kind: .package, fileExtension: "app"))
    }

    func testSymlinkUsesSymbolicLinkContentTypeWithoutReadingItsPath() {
        assertResolvedType(.symbolicLink, for: makeEntry(name: "missing-link", kind: .symlink))
    }

    func testKnownExtensionUsesFilenameContentTypeWithoutReadingItsPath() {
        assertResolvedType(.pdf, for: makeEntry(name: "missing.pdf", kind: .file, fileExtension: "pdf"))
    }

    func testExtensionlessFileUsesDataContentTypeWithoutReadingItsPath() {
        assertResolvedType(.data, for: makeEntry(name: "missing-file", kind: .file))
    }

    private func assertResolvedType(
        _ expectedType: UTType,
        for entry: FileEntry,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sourceIcon = NSImage(size: NSSize(width: 128, height: 128))
        let requestedSize = NSSize(width: 23, height: 29)
        var receivedTypes: [UTType] = []

        let icon = FileEntryIconResolver.icon(
            for: entry,
            size: requestedSize,
            contentTypeIconProvider: { contentType in
                receivedTypes.append(contentType)
                return sourceIcon
            }
        )

        XCTAssertEqual(receivedTypes, [expectedType], file: file, line: line)
        XCTAssertEqual(icon.size, requestedSize, file: file, line: line)
        XCTAssertEqual(sourceIcon.size, NSSize(width: 128, height: 128), file: file, line: line)
    }

    private func makeEntry(
        name: String,
        kind: FileEntryKind,
        fileExtension: String = ""
    ) -> FileEntry {
        FileEntry(
            url: URL(fileURLWithPath: "/definitely-not-present/\(name)"),
            name: name,
            kind: kind,
            typeDescription: "Test entry",
            fileExtension: fileExtension,
            size: nil,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: kind == .folder || kind == .package,
            isReadable: true
        )
    }
}
