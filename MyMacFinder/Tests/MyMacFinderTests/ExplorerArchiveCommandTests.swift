import Foundation
import XCTest
@testable import MyMacFinder

private final class ExtractingArchiveBrowser: ArchiveBrowsing, @unchecked Sendable {
    var extractedURL: URL

    init(extractedURL: URL) {
        self.extractedURL = extractedURL
    }

    func canOpen(_ url: URL) -> Bool { url.pathExtension == "zip" }
    func list(_ location: ArchiveLocation, showHiddenFiles: Bool) async throws -> [ArchiveEntry] { [] }
    func temporaryExtract(_ location: ArchiveLocation) async throws -> TemporaryArchiveArtifact {
        let ownerDirectoryURL = URL(fileURLWithPath: "/tmp", isDirectory: true)
        return TemporaryArchiveArtifact(
            url: extractedURL,
            ownerDirectoryURL: ownerDirectoryURL,
            ownerIdentifier: UUID(),
            expectedOwnerIdentity: try XCTUnwrap(FileSystemPathIdentity.entryIdentity(ownerDirectoryURL))
        )
    }
}

private final class CancellingArchiveBrowser: ArchiveBrowsing, @unchecked Sendable {
    func canOpen(_ url: URL) -> Bool { url.pathExtension == "zip" }
    func list(_ location: ArchiveLocation, showHiddenFiles: Bool) async throws -> [ArchiveEntry] { [] }

    func temporaryExtract(_ location: ArchiveLocation) async throws -> TemporaryArchiveArtifact {
        throw CancellationError()
    }
}

private final class LifecycleArchiveBrowser: ArchiveBrowsing, @unchecked Sendable {
    let artifact: TemporaryArchiveArtifact
    var events: [String] = []
    var cleanupError: Error?
    var releaseError: Error?
    var validationError: Error?

    init(artifact: TemporaryArchiveArtifact, cleanupError: Error? = nil) {
        self.artifact = artifact
        self.cleanupError = cleanupError
    }

    func canOpen(_ url: URL) -> Bool { url.pathExtension == "zip" }
    func list(_ location: ArchiveLocation, showHiddenFiles: Bool) async throws -> [ArchiveEntry] { [] }

    func temporaryExtract(_ location: ArchiveLocation) async throws -> TemporaryArchiveArtifact {
        events.append("extract")
        return artifact
    }

    func retainTemporaryArtifactForExternalOpen(
        _ artifact: TemporaryArchiveArtifact,
        openedAt: Date
    ) async throws {
        events.append("retain")
    }

    func releaseTemporaryArtifact(_ artifact: TemporaryArchiveArtifact) async throws {
        events.append("release")
        if let releaseError {
            throw releaseError
        }
    }

    func scheduleTemporaryArtifactCleanupRetry(_ artifact: TemporaryArchiveArtifact) async throws {
        events.append("retry")
    }

    func validateTemporaryArtifactForHandoff(_ artifact: TemporaryArchiveArtifact) async throws {
        events.append("validate")
        if let validationError {
            throw validationError
        }
    }

    func cleanupExpiredTemporaryArtifacts(now: Date, retentionInterval: TimeInterval) async throws {
        events.append("cleanup")
        if let cleanupError {
            throw cleanupError
        }
    }
}

@MainActor
private final class ArchiveOpenLauncher: ExternalAppLaunching {
    private let events: LifecycleArchiveBrowser
    private let error: Error?

    init(events: LifecycleArchiveBrowser, error: Error? = nil) {
        self.events = events
        self.error = error
    }

    func openDefault(_ url: URL) throws {
        events.events.append("open")
        if let error {
            throw error
        }
    }

    func open(_ urls: [URL], with application: OpenWithApplication) async throws {}
    func openTerminal(at directory: URL) async throws {}
    func openVSCode(at target: URL) async throws {}
    func applications(toOpen url: URL) -> [OpenWithApplication] { [] }
}

@MainActor
private final class CapturingQuickLookService: QuickLooking {
    var sessions: [QuickLookPreviewSession] = []
    var presentationError: ExplorerError?

    func preview(_ session: QuickLookPreviewSession) throws {
        if let presentationError {
            throw presentationError
        }
        sessions.append(session)
    }
}

@MainActor
private final class CountingDefaultOpenLauncher: ExternalAppLaunching {
    private(set) var openDefaultURLs: [URL] = []

    func openDefault(_ url: URL) throws {
        openDefaultURLs.append(url)
    }

    func open(_ urls: [URL], with application: OpenWithApplication) async throws {}
    func openTerminal(at directory: URL) async throws {}
    func openVSCode(at target: URL) async throws {}
    func applications(toOpen url: URL) -> [OpenWithApplication] { [] }
}

private actor TransactionArchiveBrowser: ArchiveBrowsing {
    enum ExtractionStep: @unchecked Sendable {
        case artifact(TemporaryArchiveArtifact)
        case failure(any Error)
        case suspended(TemporaryArchiveArtifact)
    }

    enum Event: Equatable, Sendable {
        case extract(String)
        case retain(URL)
        case schedule(URL)
        case validate(URL)
        case release(URL)
    }

    private var steps: [ExtractionStep]
    private var recordedEvents: [Event] = []
    private var suspendedContinuation: CheckedContinuation<TemporaryArchiveArtifact, any Error>?
    private var suspendedArtifact: TemporaryArchiveArtifact?
    private let scheduleError: (any Error)?
    private let validationError: (any Error)?

    init(
        steps: [ExtractionStep],
        scheduleError: (any Error)? = nil,
        validationError: (any Error)? = nil
    ) {
        self.steps = steps
        self.scheduleError = scheduleError
        self.validationError = validationError
    }

    nonisolated func canOpen(_ url: URL) -> Bool { url.pathExtension == "zip" }
    func list(_ location: ArchiveLocation, showHiddenFiles: Bool) async throws -> [ArchiveEntry] { [] }

    func temporaryExtract(_ location: ArchiveLocation) async throws -> TemporaryArchiveArtifact {
        recordedEvents.append(.extract(location.internalPath))
        guard !steps.isEmpty else {
            throw ExplorerError.readFailed("Unexpected extraction")
        }
        switch steps.removeFirst() {
        case .artifact(let artifact):
            return artifact
        case .failure(let error):
            throw error
        case .suspended(let artifact):
            return try await withCheckedThrowingContinuation { continuation in
                suspendedArtifact = artifact
                suspendedContinuation = continuation
            }
        }
    }

    func releaseTemporaryArtifact(_ artifact: TemporaryArchiveArtifact) async throws {
        recordedEvents.append(.release(artifact.url))
    }

    func scheduleTemporaryArtifactCleanupRetry(_ artifact: TemporaryArchiveArtifact) async throws {
        recordedEvents.append(.schedule(artifact.url))
        if let scheduleError {
            throw scheduleError
        }
    }

    func retainTemporaryArtifactForExternalOpen(
        _ artifact: TemporaryArchiveArtifact,
        openedAt: Date
    ) async throws {
        recordedEvents.append(.retain(artifact.url))
    }

    func validateTemporaryArtifactForHandoff(_ artifact: TemporaryArchiveArtifact) async throws {
        recordedEvents.append(.validate(artifact.url))
        if let validationError {
            throw validationError
        }
    }

    func events() -> [Event] {
        recordedEvents
    }

    func waitUntilExtractionSuspends() async {
        while suspendedContinuation == nil {
            await Task.yield()
        }
    }

    func resumeSuspendedExtraction() {
        guard let artifact = suspendedArtifact else {
            suspendedContinuation?.resume(throwing: ExplorerError.readFailed("Missing suspended artifact"))
            suspendedContinuation = nil
            return
        }
        suspendedArtifact = nil
        suspendedContinuation?.resume(returning: artifact)
        suspendedContinuation = nil
    }

    func waitForReleaseCount(_ expectedCount: Int) async {
        while recordedEvents.reduce(into: 0, { count, event in
            if case .release = event { count += 1 }
        }) < expectedCount {
            await Task.yield()
        }
    }
}

@MainActor
final class ExplorerArchiveCommandTests: XCTestCase {
    func testOpeningArchiveEntryRegistersArtifactBeforeLaunching() async throws {
        let browser = LifecycleArchiveBrowser(artifact: try makeTemporaryArtifact())
        let launcher = ArchiveOpenLauncher(events: browser)
        let store = ExplorerStore(
            archiveBrowser: browser,
            directoryWatcher: nil,
            externalAppLauncher: launcher
        )
        let location = ArchiveLocation(
            archiveURL: URL(fileURLWithPath: "/tmp/sample.zip"),
            internalPath: "readme.txt"
        )
        store.replaceActivePaneForTesting(
            location: .archive(location.parent),
            entries: [archiveEntry(at: location)],
            selectedURLs: [location.virtualURL]
        )

        await store.open(location.virtualURL)

        XCTAssertEqual(browser.events, ["extract", "retain", "validate", "open"])
        XCTAssertNil(store.visibleError)
    }

    func testArchiveOpenFailureReleasesArtifactAndPresentsOriginalError() async throws {
        let browser = LifecycleArchiveBrowser(artifact: try makeTemporaryArtifact())
        let launcher = ArchiveOpenLauncher(
            events: browser,
            error: ExplorerError.externalCommandFailed("No application could open: /tmp/readme.txt")
        )
        let store = ExplorerStore(
            archiveBrowser: browser,
            directoryWatcher: nil,
            externalAppLauncher: launcher
        )
        let location = ArchiveLocation(
            archiveURL: URL(fileURLWithPath: "/tmp/sample.zip"),
            internalPath: "readme.txt"
        )
        store.replaceActivePaneForTesting(
            location: .archive(location.parent),
            entries: [archiveEntry(at: location)],
            selectedURLs: [location.virtualURL]
        )

        await store.open(location.virtualURL)

        XCTAssertEqual(browser.events, ["extract", "retain", "validate", "open", "release"])
        XCTAssertEqual(store.visibleError, .externalCommandFailed("No application could open: /tmp/readme.txt"))
    }

    func testArchiveOpenRevalidatesArtifactImmediatelyBeforeDefaultOpen() async throws {
        let artifact = try makeTemporaryArtifact()
        let browser = LifecycleArchiveBrowser(artifact: artifact)
        browser.validationError = ExplorerError.operationFailed("artifact identity changed")
        let launcher = ArchiveOpenLauncher(events: browser)
        let store = ExplorerStore(
            archiveBrowser: browser,
            directoryWatcher: nil,
            externalAppLauncher: launcher
        )
        let location = ArchiveLocation(
            archiveURL: URL(fileURLWithPath: "/tmp/sample.zip"),
            internalPath: "readme.txt"
        )
        store.replaceActivePaneForTesting(
            location: .archive(location.parent),
            entries: [archiveEntry(at: location)],
            selectedURLs: [location.virtualURL]
        )

        await store.open(location.virtualURL)

        XCTAssertEqual(browser.events, ["extract", "retain", "validate", "release"])
        XCTAssertEqual(store.visibleError, .operationFailed("artifact identity changed"))
    }

    func testArchiveOpenFailurePreservesExplorerErrorWhenReleaseFails() async throws {
        let browser = LifecycleArchiveBrowser(artifact: try makeTemporaryArtifact())
        browser.releaseError = ArchiveCleanupFailure()
        let launcher = ArchiveOpenLauncher(
            events: browser,
            error: ExplorerError.externalCommandFailed("No application could open: /tmp/readme.txt")
        )
        let store = ExplorerStore(
            archiveBrowser: browser,
            directoryWatcher: nil,
            externalAppLauncher: launcher
        )
        let location = ArchiveLocation(
            archiveURL: URL(fileURLWithPath: "/tmp/sample.zip"),
            internalPath: "readme.txt"
        )
        store.replaceActivePaneForTesting(
            location: .archive(location.parent),
            entries: [archiveEntry(at: location)],
            selectedURLs: [location.virtualURL]
        )

        await store.open(location.virtualURL)

        XCTAssertEqual(browser.events, ["extract", "retain", "validate", "open", "release"])
        XCTAssertEqual(
            store.visibleError,
            .externalCommandFailed(
                "No application could open: /tmp/readme.txt; temporary artifact cleanup failed at "
                    + "\(browser.artifact.ownerDirectoryURL.path): release cleanup failed"
            )
        )
    }

    func testArchiveOpenCancellationSchedulesCleanupRetryWithoutShowingError() async throws {
        let browser = LifecycleArchiveBrowser(artifact: try makeTemporaryArtifact())
        browser.releaseError = ArchiveCleanupFailure()
        let launcher = ArchiveOpenLauncher(events: browser, error: CancellationError())
        let store = ExplorerStore(
            archiveBrowser: browser,
            directoryWatcher: nil,
            externalAppLauncher: launcher
        )
        let location = ArchiveLocation(
            archiveURL: URL(fileURLWithPath: "/tmp/sample.zip"),
            internalPath: "readme.txt"
        )
        store.replaceActivePaneForTesting(
            location: .archive(location.parent),
            entries: [archiveEntry(at: location)],
            selectedURLs: [location.virtualURL]
        )

        await store.open(location.virtualURL)

        XCTAssertEqual(browser.events, ["extract", "retain", "validate", "open", "release", "retry"])
        XCTAssertNil(store.visibleError)
    }

    func testStartupCleanupFailureDoesNotPreventInitialListing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
        }
        let listedFile = directory.appendingPathComponent("listed.txt")
        try "listed".write(to: listedFile, atomically: true, encoding: .utf8)
        let browser = LifecycleArchiveBrowser(
            artifact: try makeTemporaryArtifact(),
            cleanupError: ExplorerError.operationFailed("registry unavailable")
        )
        let store = ExplorerStore(initialURL: directory, archiveBrowser: browser, directoryWatcher: nil)
        let now = Date(timeIntervalSinceReferenceDate: 12_345)

        await store.cleanupExpiredArchiveArtifacts(now: now)
        await store.loadInitialDirectory()

        XCTAssertEqual(browser.events, ["cleanup"])
        XCTAssertEqual(store.activePane.entries.map(\.name), ["listed.txt"])
        XCTAssertEqual(
            store.visibleError,
            .operationFailed("Temporary preview cleanup failed: registry unavailable")
        )
    }

    func testStartupCleanupCancellationDoesNotShowErrorOrPreventInitialListing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
        }
        let listedFile = directory.appendingPathComponent("listed.txt")
        try "listed".write(to: listedFile, atomically: true, encoding: .utf8)
        let browser = LifecycleArchiveBrowser(
            artifact: try makeTemporaryArtifact(),
            cleanupError: CancellationError()
        )
        let store = ExplorerStore(initialURL: directory, archiveBrowser: browser, directoryWatcher: nil)

        await store.cleanupExpiredArchiveArtifacts(now: Date(timeIntervalSinceReferenceDate: 12_346))
        await store.loadInitialDirectory()

        XCTAssertEqual(browser.events, ["cleanup"])
        XCTAssertEqual(store.activePane.entries.map(\.name), ["listed.txt"])
        XCTAssertNil(store.visibleError)
    }

    func testMutationCommandsAreDisabledInsideArchive() {
        let archiveURL = URL(fileURLWithPath: "/tmp/sample.zip")
        let location = ArchiveLocation(archiveURL: archiveURL, internalPath: "readme.txt")
        let entry = FileEntry(
            url: location.virtualURL,
            name: "readme.txt",
            kind: .zipVirtualFile,
            typeDescription: "ZIP Item",
            fileExtension: "txt",
            size: 5,
            dateModified: nil,
            dateCreated: nil,
            dateAccessed: nil,
            isHidden: false,
            isDirectoryLike: false,
            isReadable: true,
            source: .archive(location)
        )

        XCTAssertFalse(ExplorerCommand.newFolder.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.rename.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.moveToTrash.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.paste.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.cut.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.compressToZip.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.calculateFolderSize.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertFalse(ExplorerCommand.editTags.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))

        XCTAssertTrue(ExplorerCommand.open.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertTrue(ExplorerCommand.quickLook.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertTrue(ExplorerCommand.copyPath.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
        XCTAssertTrue(ExplorerCommand.revealInFinder.isEnabled(selectionCount: 1, canPaste: true, selectedEntries: [entry], isArchiveLocation: true))
    }

    func testQuickLookExtractsArchiveEntryBeforePreviewing() async throws {
        let extracted = URL(fileURLWithPath: "/tmp/extracted-readme.txt")
        let archiveBrowser = ExtractingArchiveBrowser(extractedURL: extracted)
        let quickLook = CapturingQuickLookService()
        let store = ExplorerStore(
            archiveBrowser: archiveBrowser,
            directoryWatcher: nil,
            quickLookService: quickLook
        )
        let archiveLocation = ArchiveLocation(archiveURL: URL(fileURLWithPath: "/tmp/sample.zip"), internalPath: "readme.txt")
        store.replaceActivePaneForTesting(
            location: .archive(archiveLocation.parent),
            entries: [
                FileEntry(
                    url: archiveLocation.virtualURL,
                    name: "readme.txt",
                    kind: .zipVirtualFile,
                    typeDescription: "ZIP Item",
                    fileExtension: "txt",
                    size: 5,
                    dateModified: nil,
                    dateCreated: nil,
                    dateAccessed: nil,
                    isHidden: false,
                    isDirectoryLike: false,
                    isReadable: true,
                    source: .archive(archiveLocation)
                )
            ],
            selectedURLs: [archiveLocation.virtualURL]
        )

        await store.perform(.quickLook)

        XCTAssertEqual(quickLook.sessions.map(\.urls), [[extracted]])
    }

    func testQuickLookDoesNotExtractWhenServiceIsUnavailable() async throws {
        let location = ArchiveLocation(
            archiveURL: URL(fileURLWithPath: "/tmp/sample.zip"),
            internalPath: "readme.txt"
        )
        let browser = TransactionArchiveBrowser(steps: [.artifact(try makeTemporaryArtifact(named: "unused.txt"))])
        let store = makeArchivePreviewStore(browser: browser, quickLookService: nil, locations: [location])

        await store.perform(.quickLook)

        let events = await browser.events()
        XCTAssertEqual(events, [])
        XCTAssertNil(store.visibleError)
    }

    func testQuickLookLaterExtractionFailureReleasesEarlierArtifactsInReverseOrder() async throws {
        let locations = archiveLocations(named: ["first.txt", "second.txt", "third.txt"])
        let first = try makeTemporaryArtifact(named: "first.txt")
        let second = try makeTemporaryArtifact(named: "second.txt")
        let browser = TransactionArchiveBrowser(steps: [
            .artifact(first),
            .artifact(second),
            .failure(ExplorerError.readFailed("third extraction failed"))
        ])
        let quickLook = CapturingQuickLookService()
        let store = makeArchivePreviewStore(browser: browser, quickLookService: quickLook, locations: locations)

        await store.perform(.quickLook)

        let events = await browser.events()
        XCTAssertEqual(
            events,
            [
                .extract("first.txt"),
                .extract("second.txt"),
                .extract("third.txt"),
                .release(second.url),
                .release(first.url)
            ]
        )
        XCTAssertTrue(quickLook.sessions.isEmpty)
        XCTAssertEqual(store.visibleError, .readFailed("third extraction failed"))
    }

    func testQuickLookPresentationFailureReleasesPreparedArtifacts() async throws {
        let locations = archiveLocations(named: ["first.txt", "second.txt"])
        let first = try makeTemporaryArtifact(named: "first.txt")
        let second = try makeTemporaryArtifact(named: "second.txt")
        let browser = TransactionArchiveBrowser(steps: [.artifact(first), .artifact(second)])
        let quickLook = CapturingQuickLookService()
        quickLook.presentationError = .readFailed("presentation failed")
        let store = makeArchivePreviewStore(browser: browser, quickLookService: quickLook, locations: locations)

        await store.perform(.quickLook)
        await browser.waitForReleaseCount(2)

        let events = await browser.events()
        XCTAssertEqual(
            events,
            [
                .extract("first.txt"),
                .extract("second.txt"),
                .schedule(first.url),
                .schedule(second.url),
                .validate(first.url),
                .validate(second.url),
                .release(second.url),
                .release(first.url)
            ]
        )
        XCTAssertEqual(store.visibleError, .readFailed("presentation failed"))
    }

    func testQuickLookCancellationReleasesPreparedArtifactsWithoutVisibleError() async throws {
        let locations = archiveLocations(named: ["first.txt", "second.txt"])
        let first = try makeTemporaryArtifact(named: "first.txt")
        let browser = TransactionArchiveBrowser(steps: [.artifact(first), .failure(CancellationError())])
        let quickLook = CapturingQuickLookService()
        let store = makeArchivePreviewStore(browser: browser, quickLookService: quickLook, locations: locations)

        await store.perform(.quickLook)

        let events = await browser.events()
        XCTAssertEqual(
            events,
            [.extract("first.txt"), .extract("second.txt"), .release(first.url)]
        )
        XCTAssertTrue(quickLook.sessions.isEmpty)
        XCTAssertNil(store.visibleError)
    }

    func testCancellingParentQuickLookTaskAfterNonCooperativeExtractionReleasesWithoutPresenting() async throws {
        let location = archiveLocations(named: ["suspended.txt"])[0]
        let artifact = try makeTemporaryArtifact(named: "suspended-preview.txt")
        let browser = TransactionArchiveBrowser(steps: [.suspended(artifact)])
        let quickLook = CapturingQuickLookService()
        let store = makeArchivePreviewStore(browser: browser, quickLookService: quickLook, locations: [location])
        let task = Task { @MainActor in
            await store.perform(.quickLook)
        }
        await browser.waitUntilExtractionSuspends()

        task.cancel()
        await browser.resumeSuspendedExtraction()
        await task.value

        let events = await browser.events()
        XCTAssertEqual(events, [.extract("suspended.txt"), .release(artifact.url)])
        XCTAssertTrue(quickLook.sessions.isEmpty)
        XCTAssertNil(store.visibleError)
    }

    func testCancellingParentArchiveOpenTaskAfterNonCooperativeExtractionDoesNotRetainOrLaunch() async throws {
        let location = archiveLocations(named: ["suspended.txt"])[0]
        let artifact = try makeTemporaryArtifact(named: "suspended-open.txt")
        let browser = TransactionArchiveBrowser(steps: [.suspended(artifact)])
        let launcher = CountingDefaultOpenLauncher()
        let store = ExplorerStore(
            archiveBrowser: browser,
            directoryWatcher: nil,
            externalAppLauncher: launcher
        )
        store.replaceActivePaneForTesting(
            location: .archive(location.parent),
            entries: [archiveEntry(at: location)],
            selectedURLs: [location.virtualURL]
        )
        let task = Task { @MainActor in
            await store.open(location.virtualURL)
        }
        await browser.waitUntilExtractionSuspends()

        task.cancel()
        await browser.resumeSuspendedExtraction()
        await task.value

        let events = await browser.events()
        XCTAssertEqual(events, [.extract("suspended.txt"), .release(artifact.url)])
        XCTAssertTrue(launcher.openDefaultURLs.isEmpty)
        XCTAssertNil(store.visibleError)
    }

    func testQuickLookRegistersDurableCleanupOwnershipBeforePresentation() async throws {
        let location = archiveLocations(named: ["durable.txt"])[0]
        let artifact = try makeTemporaryArtifact(named: "durable-preview.txt")
        let browser = TransactionArchiveBrowser(steps: [.artifact(artifact)])
        let quickLook = CapturingQuickLookService()
        let store = makeArchivePreviewStore(browser: browser, quickLookService: quickLook, locations: [location])

        await store.perform(.quickLook)

        let events = await browser.events()
        XCTAssertEqual(
            events,
            [.extract("durable.txt"), .schedule(artifact.url), .validate(artifact.url)]
        )
        XCTAssertEqual(quickLook.sessions.map(\.urls), [[artifact.url]])
    }

    func testQuickLookRevalidatesArtifactImmediatelyBeforePresentation() async throws {
        let location = archiveLocations(named: ["identity-change.txt"])[0]
        let artifact = try makeTemporaryArtifact(named: "identity-change-preview.txt")
        let browser = TransactionArchiveBrowser(
            steps: [.artifact(artifact)],
            validationError: ExplorerError.operationFailed("artifact identity changed")
        )
        let quickLook = CapturingQuickLookService()
        let store = makeArchivePreviewStore(browser: browser, quickLookService: quickLook, locations: [location])

        await store.perform(.quickLook)

        let events = await browser.events()
        XCTAssertEqual(
            events,
            [
                .extract("identity-change.txt"),
                .schedule(artifact.url),
                .validate(artifact.url),
                .release(artifact.url)
            ]
        )
        XCTAssertTrue(quickLook.sessions.isEmpty)
        XCTAssertEqual(store.visibleError, .operationFailed("artifact identity changed"))
    }

    func testQuickLookCleanupRegistrationFailurePreventsPresentationAndReleasesArtifact() async throws {
        let location = archiveLocations(named: ["registration-failure.txt"])[0]
        let artifact = try makeTemporaryArtifact(named: "registration-failure-preview.txt")
        let browser = TransactionArchiveBrowser(
            steps: [.artifact(artifact)],
            scheduleError: ExplorerError.operationFailed("cleanup registration failed")
        )
        let quickLook = CapturingQuickLookService()
        let store = makeArchivePreviewStore(browser: browser, quickLookService: quickLook, locations: [location])

        await store.perform(.quickLook)

        let events = await browser.events()
        XCTAssertEqual(
            events,
            [
                .extract("registration-failure.txt"),
                .schedule(artifact.url),
                .release(artifact.url)
            ]
        )
        XCTAssertTrue(quickLook.sessions.isEmpty)
        XCTAssertEqual(store.visibleError, .operationFailed("cleanup registration failed"))
    }

    func testQuickLookCompletionAfterTabIDChangeDoesNotPresentAndReleasesArtifacts() async throws {
        try await assertQuickLookRejectsStaleContext(afterChanging: .tabID)
    }

    func testQuickLookCompletionAfterPaneIDChangeDoesNotPresentAndReleasesArtifacts() async throws {
        try await assertQuickLookRejectsStaleContext(afterChanging: .paneID)
    }

    func testQuickLookCompletionAfterPaneLocationChangeDoesNotPresentAndReleasesArtifacts() async throws {
        try await assertQuickLookRejectsStaleContext(afterChanging: .paneLocation)
    }

    func testQuickLookCompletionAfterSelectedURLsChangeDoesNotPresentAndReleasesArtifacts() async throws {
        try await assertQuickLookRejectsStaleContext(afterChanging: .selectedURLs)
    }

    func testQuickLookCompletionAfterSearchScopeChangeDoesNotPresentAndReleasesArtifacts() async throws {
        try await assertQuickLookRejectsStaleContext(afterChanging: .searchScope)
    }

    func testQuickLookCompletionAfterOrdinaryQueryChangeDoesNotPresentAndReleasesArtifacts() async throws {
        try await assertQuickLookRejectsStaleContext(afterChanging: .ordinaryQuery)
    }

    func testQuickLookCompletionAfterExplicitTagQueryChangeDoesNotPresentAndReleasesArtifacts() async throws {
        try await assertQuickLookRejectsStaleContext(afterChanging: .explicitTagQuery)
    }

    func testQuickLookCompletionDoesNotChangeSearchContext() async throws {
        let location = archiveLocations(named: ["readme.txt"])[0]
        let artifact = try makeTemporaryArtifact(named: "readme.txt")
        let browser = TransactionArchiveBrowser(steps: [.artifact(artifact)])
        let quickLook = CapturingQuickLookService()
        let store = makeArchivePreviewStore(browser: browser, quickLookService: quickLook, locations: [location])
        store.setSearchScope(.recursive)
        store.setSearchQuery("readme")
        store.setSearchFinderTagQuery("Work")
        store.updateSelection([location.virtualURL])
        let originalTabID = store.activeTab.id
        let originalPaneID = store.activePane.id
        let originalPaneLocation = store.activePane.location
        let originalSelectedURLs = store.activePane.selectedURLs
        let originalSearchOptions = store.searchOptions
        let originalSearchQuery = store.searchQuery

        await store.perform(.quickLook)

        XCTAssertEqual(quickLook.sessions.map(\.urls), [[artifact.url]])
        XCTAssertEqual(store.activeTab.id, originalTabID)
        XCTAssertEqual(store.activePane.id, originalPaneID)
        XCTAssertEqual(store.activePane.location, originalPaneLocation)
        XCTAssertEqual(store.activePane.selectedURLs, originalSelectedURLs)
        XCTAssertEqual(store.searchOptions, originalSearchOptions)
        XCTAssertEqual(store.searchQuery, originalSearchQuery)
        XCTAssertNil(store.visibleError)
    }

    func testOpeningArchiveEntryDoesNotShowErrorForCancelledExtraction() async {
        let archiveBrowser = CancellingArchiveBrowser()
        let store = ExplorerStore(archiveBrowser: archiveBrowser, directoryWatcher: nil)
        let archiveLocation = ArchiveLocation(
            archiveURL: URL(fileURLWithPath: "/tmp/sample.zip"),
            internalPath: "readme.txt"
        )
        store.replaceActivePaneForTesting(
            location: .archive(archiveLocation.parent),
            entries: [
                FileEntry(
                    url: archiveLocation.virtualURL,
                    name: "readme.txt",
                    kind: .zipVirtualFile,
                    typeDescription: "ZIP Item",
                    fileExtension: "txt",
                    size: 5,
                    dateModified: nil,
                    dateCreated: nil,
                    dateAccessed: nil,
                    isHidden: false,
                    isDirectoryLike: false,
                    isReadable: true,
                    source: .archive(archiveLocation)
                )
            ],
            selectedURLs: [archiveLocation.virtualURL]
        )

        await store.open(archiveLocation.virtualURL)

        XCTAssertNil(store.visibleError)
    }
}

private struct ArchiveCleanupFailure: LocalizedError {
    var errorDescription: String? { "release cleanup failed" }
}

private func makeTemporaryArtifact(named name: String = "readme.txt") throws -> TemporaryArchiveArtifact {
    let ownerDirectoryURL = FileManager.default.temporaryDirectory
    return TemporaryArchiveArtifact(
        url: ownerDirectoryURL.appendingPathComponent(name),
        ownerDirectoryURL: ownerDirectoryURL,
        ownerIdentifier: UUID(),
        expectedOwnerIdentity: try XCTUnwrap(FileSystemPathIdentity.entryIdentity(ownerDirectoryURL))
    )
}

private func archiveLocations(named names: [String]) -> [ArchiveLocation] {
    let archiveURL = URL(fileURLWithPath: "/tmp/sample.zip")
    return names.map { ArchiveLocation(archiveURL: archiveURL, internalPath: $0) }
}

@MainActor
private func makeArchivePreviewStore(
    browser: any ArchiveBrowsing,
    quickLookService: (any QuickLooking)?,
    locations: [ArchiveLocation]
) -> ExplorerStore {
    let store = ExplorerStore(
        archiveBrowser: browser,
        directoryWatcher: nil,
        quickLookService: quickLookService
    )
    let entries = locations.map { location in
        archiveEntry(at: location, finderTags: [FinderTag("Work"), FinderTag("Other")])
    }
    store.replaceActivePaneForTesting(
        location: .archive(locations[0].parent),
        entries: entries,
        selectedURLs: Set(locations.map(\.virtualURL))
    )
    return store
}

private enum QuickLookContextMutation: Equatable {
    case tabID
    case paneID
    case paneLocation
    case selectedURLs
    case searchScope
    case ordinaryQuery
    case explicitTagQuery
}

private struct QuickLookContextSnapshot: Equatable {
    var tabID: ExplorerTabID
    var paneID: PaneID
    var paneLocation: PaneLocation
    var selectedURLs: Set<URL>
    var searchScope: SearchScope
    var ordinaryQuery: String
    var explicitTagQuery: String
}

@MainActor
private func assertQuickLookRejectsStaleContext(afterChanging mutation: QuickLookContextMutation) async throws {
    let locations = archiveLocations(named: ["first.txt", "second.txt"])
    let first = try makeTemporaryArtifact(named: "first-preview.txt")
    let second = try makeTemporaryArtifact(named: "second-preview.txt")
    let browser = TransactionArchiveBrowser(steps: [.artifact(first), .suspended(second)])
    let quickLook = CapturingQuickLookService()
    let store = makeArchivePreviewStore(browser: browser, quickLookService: quickLook, locations: locations)
    store.setSearchScope(.recursive)
    store.setSearchQuery("txt")
    store.setSearchFinderTagQuery("Work")
    store.updateSelection(Set(locations.map(\.virtualURL)))
    let originalContext = quickLookContext(of: store)

    let previewTask = Task { @MainActor in
        await store.perform(.quickLook)
    }
    await browser.waitUntilExtractionSuspends()

    mutateQuickLookContext(mutation, in: store, locations: locations)
    let changedContext = quickLookContext(of: store)
    assertOnlyExpectedContextValueChanged(mutation, from: originalContext, to: changedContext)

    await browser.resumeSuspendedExtraction()
    await previewTask.value

    XCTAssertTrue(quickLook.sessions.isEmpty)
    let events = await browser.events()
    XCTAssertEqual(
        events,
        [
            .extract("first.txt"),
            .extract("second.txt"),
            .release(second.url),
            .release(first.url)
        ]
    )
    XCTAssertEqual(quickLookContext(of: store), changedContext)
    XCTAssertNil(store.visibleError)
}

@MainActor
private func mutateQuickLookContext(
    _ mutation: QuickLookContextMutation,
    in store: ExplorerStore,
    locations: [ArchiveLocation]
) {
    switch mutation {
    case .tabID:
        store.replaceActiveTabIDForTesting()
    case .paneID:
        store.replaceActivePaneIDForTesting()
    case .paneLocation:
        let changedLocation = ArchiveLocation(
            archiveURL: URL(fileURLWithPath: "/tmp/changed.zip"),
            internalPath: ""
        )
        store.replaceActivePaneForTesting(
            location: .archive(changedLocation),
            entries: store.activePane.entries,
            selectedURLs: store.activePane.selectedURLs
        )
    case .selectedURLs:
        store.updateSelection([locations[0].virtualURL])
    case .searchScope:
        store.setSearchScope(.currentFolder)
    case .ordinaryQuery:
        store.setSearchQuery("t")
    case .explicitTagQuery:
        store.setSearchFinderTagQuery("Other")
    }
}

@MainActor
private func quickLookContext(of store: ExplorerStore) -> QuickLookContextSnapshot {
    QuickLookContextSnapshot(
        tabID: store.activeTab.id,
        paneID: store.activePane.id,
        paneLocation: store.activePane.location,
        selectedURLs: store.activePane.selectedURLs,
        searchScope: store.searchOptions.scope,
        ordinaryQuery: store.searchQuery,
        explicitTagQuery: store.searchOptions.finderTagQuery
    )
}

private func assertOnlyExpectedContextValueChanged(
    _ mutation: QuickLookContextMutation,
    from original: QuickLookContextSnapshot,
    to changed: QuickLookContextSnapshot,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(original.tabID == changed.tabID, mutation != .tabID, file: file, line: line)
    XCTAssertEqual(original.paneID == changed.paneID, mutation != .paneID, file: file, line: line)
    XCTAssertEqual(original.paneLocation == changed.paneLocation, mutation != .paneLocation, file: file, line: line)
    XCTAssertEqual(original.selectedURLs == changed.selectedURLs, mutation != .selectedURLs, file: file, line: line)
    XCTAssertEqual(original.searchScope == changed.searchScope, mutation != .searchScope, file: file, line: line)
    XCTAssertEqual(original.ordinaryQuery == changed.ordinaryQuery, mutation != .ordinaryQuery, file: file, line: line)
    XCTAssertEqual(
        original.explicitTagQuery == changed.explicitTagQuery,
        mutation != .explicitTagQuery,
        file: file,
        line: line
    )
}

private func archiveEntry(at location: ArchiveLocation, finderTags: [FinderTag] = []) -> FileEntry {
    FileEntry(
        url: location.virtualURL,
        name: location.internalPath.split(separator: "/").last.map(String.init) ?? "readme.txt",
        kind: .zipVirtualFile,
        typeDescription: "ZIP Item",
        fileExtension: "txt",
        size: 5,
        dateModified: nil,
        dateCreated: nil,
        dateAccessed: nil,
        isHidden: false,
        isDirectoryLike: false,
        isReadable: true,
        finderTags: finderTags,
        source: .archive(location)
    )
}
