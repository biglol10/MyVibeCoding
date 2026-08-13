import Foundation
import XCTest
@testable import CaptureStudio

final class PendingRecordingStoreTests: XCTestCase {
    func testMediaValidatorRejectsNonVideoFile() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("damaged.mp4")
        try Data("not a video".utf8).write(to: fileURL)

        let isRecoverable = await PendingRecordingMediaValidator().isRecoverableRecording(at: fileURL)

        XCTAssertFalse(isRecoverable)
    }

    func testAllocatesUniqueMP4URLsInsideOwnedDirectory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingRecordingStore(directoryURL: directory)

        let firstURL = try store.allocateRecordingURL()
        let secondURL = try store.allocateRecordingURL()

        XCTAssertEqual(firstURL.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        XCTAssertEqual(firstURL.pathExtension, "mp4")
        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertTrue(store.owns(firstURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
    }

    func testAllocationRestrictsExistingRecoveryDirectoryToCurrentUser() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o777]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: directory.path)
        let store = PendingRecordingStore(directoryURL: directory)

        _ = try store.allocateRecordingURL()

        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertEqual(permissions & 0o777, 0o700)
    }

    func testAllocationRejectsSymlinkRecoveryDirectoryWithoutChangingTargetPermissions() throws {
        let parentDirectory = temporaryDirectory()
        let targetDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: parentDirectory)
            try? FileManager.default.removeItem(at: targetDirectory)
        }
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: targetDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: targetDirectory.path)
        let recoveryDirectory = parentDirectory.appendingPathComponent("PendingRecordings", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: recoveryDirectory, withDestinationURL: targetDirectory)
        let store = PendingRecordingStore(directoryURL: recoveryDirectory)

        XCTAssertThrowsError(try store.allocateRecordingURL())

        let attributes = try FileManager.default.attributesOfItem(atPath: targetDirectory.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertEqual(permissions & 0o777, 0o755)
        let externalURL = targetDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        XCTAssertFalse(store.owns(externalURL))
    }

    func testAllocationRejectsSymlinkInManagedDirectoryChain() throws {
        let baseDirectory = temporaryDirectory()
        let targetDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: baseDirectory)
            try? FileManager.default.removeItem(at: targetDirectory)
        }
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let linkedAppDirectory = baseDirectory.appendingPathComponent("CaptureStudio", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedAppDirectory, withDestinationURL: targetDirectory)
        let store = PendingRecordingStore(
            baseDirectoryURL: baseDirectory,
            managedDirectoryComponents: ["CaptureStudio", "PendingRecordings"]
        )

        XCTAssertThrowsError(try store.allocateRecordingURL())
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: targetDirectory.appendingPathComponent("PendingRecordings").path
        ))
    }

    func testAllocationCreatesMissingTrustedBaseAndManagedDirectories() throws {
        let containerDirectory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: containerDirectory) }
        let baseDirectory = containerDirectory.appendingPathComponent("Application Support", isDirectory: true)
        let store = PendingRecordingStore(
            baseDirectoryURL: baseDirectory,
            managedDirectoryComponents: ["CaptureStudio", "PendingRecordings"]
        )

        let recordingURL = try store.allocateRecordingURL()

        XCTAssertEqual(
            recordingURL.deletingLastPathComponent(),
            baseDirectory
                .appendingPathComponent("CaptureStudio", isDirectory: true)
                .appendingPathComponent("PendingRecordings", isDirectory: true)
        )
        XCTAssertTrue(store.owns(recordingURL))
    }

    func testReplacingValidatedRecoveryDirectoryInvalidatesOwnership() throws {
        let parentDirectory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parentDirectory) }
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        let recoveryDirectory = parentDirectory.appendingPathComponent("PendingRecordings", isDirectory: true)
        let store = PendingRecordingStore(directoryURL: recoveryDirectory)
        let originalURL = try store.allocateRecordingURL()
        try Data("original".utf8).write(to: originalURL)
        XCTAssertTrue(store.owns(originalURL))

        let replacedDirectory = parentDirectory.appendingPathComponent("replaced", isDirectory: true)
        try FileManager.default.moveItem(at: recoveryDirectory, to: replacedDirectory)
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: false)
        let replacementURL = recoveryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        try Data("replacement".utf8).write(to: replacementURL)

        XCTAssertFalse(store.owns(replacementURL))
        XCTAssertThrowsError(try store.recoverableRecordings())
    }

    func testRecoverableRecordingsReturnsNewestOwnedNonemptyRegularFileOnly() throws {
        let directory = temporaryDirectory()
        let outsideDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: outsideDirectory)
        }
        let store = PendingRecordingStore(directoryURL: directory)
        let olderURL = try store.allocateRecordingURL()
        let newerURL = try store.allocateRecordingURL()
        try Data("older".utf8).write(to: olderURL)
        try Data("newer".utf8).write(to: newerURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: olderURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)],
            ofItemAtPath: newerURL.path
        )

        let invalidNameURL = directory.appendingPathComponent("not-owned.mp4")
        try Data("ignore".utf8).write(to: invalidNameURL)
        let emptyURL = try store.allocateRecordingURL()
        XCTAssertTrue(FileManager.default.createFile(atPath: emptyURL.path, contents: Data()))
        let externalTarget = outsideDirectory.appendingPathComponent("external.mp4")
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        try Data("external".utf8).write(to: externalTarget)
        let symlinkURL = try store.allocateRecordingURL()
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: externalTarget)
        let worldWritableURL = try store.allocateRecordingURL()
        try Data("unsafe".utf8).write(to: worldWritableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: worldWritableURL.path)

        let recordings = try store.recoverableRecordings()

        XCTAssertEqual(recordings.map(\.fileURL), [newerURL, olderURL])
        XCTAssertEqual(recordings.map(\.createdAt), [
            Date(timeIntervalSince1970: 200),
            Date(timeIntervalSince1970: 100)
        ])
        XCTAssertTrue(recordings.allSatisfy { $0.fileIdentity.matchesExistingFile(at: $0.fileURL) })
        XCTAssertFalse(store.owns(invalidNameURL))
        XCTAssertFalse(store.owns(externalTarget))
    }

    func testRecoveryTightensExistingDirectoryPermissionsBeforeReading() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let allocatingStore = PendingRecordingStore(directoryURL: directory)
        let fileURL = try allocatingStore.allocateRecordingURL()
        try Data("recording candidate".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: directory.path)

        let recoveringStore = PendingRecordingStore(directoryURL: directory)
        _ = try recoveringStore.recoverableRecordings()

        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
        XCTAssertEqual(permissions & 0o777, 0o700)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PendingRecordingStoreTests-\(UUID().uuidString)", isDirectory: true)
    }
}
