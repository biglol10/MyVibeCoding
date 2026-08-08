# Archive Preview Lifecycle And Responsiveness Design Spec

Date: 2026-08-08

## Purpose

MyMacFinder currently extracts ZIP entries into a temporary preview directory but does not consistently remove those files. A failed or cancelled multi-item Quick Look request can leave earlier extractions behind, and files opened in an external application have no bounded retention policy. Rapid selection changes can also leave obsolete Quick Look thumbnail work running after the UI has moved to another item.

This design gives every temporary archive extraction an explicit owner and lifetime. It also makes default-open failures visible and cancels obsolete thumbnail work so preview activity cannot accumulate during normal browsing.

## Scope

Included:

- Managed ownership for temporary ZIP extraction artifacts.
- Immediate cleanup for Quick Look close, replacement, failure, and cancellation.
- A 24-hour retention policy for ZIP entries successfully opened in an external application.
- Startup cleanup of expired external-open artifacts.
- Transactional cleanup for partially completed multi-item preview preparation.
- Visible errors when macOS cannot open a file with its default application.
- Cancellation of obsolete Quick Look thumbnail requests.
- A metadata-based preview fallback icon that does not synchronously inspect the selected path.
- Automated regression coverage using UUID-scoped system temporary directories.

Excluded:

- Changing ZIP browsing, extraction, or archive editing features visible to the user.
- Cleaning temporary files created by other applications.
- Deleting arbitrary contents of the system temporary directory.
- Notarization, Developer ID distribution, or broader application architecture changes.

## User-Visible Behavior

- Quick Look works as before, but extracted ZIP files are removed when the Quick Look panel closes or is replaced.
- If preparing several Quick Look items fails or is cancelled, files already prepared for that request are removed.
- A ZIP entry opened in another application remains available long enough for that application to read it. It becomes eligible for cleanup after 24 hours and is removed during a later MyMacFinder launch.
- If macOS cannot open a file, MyMacFinder shows an operation error instead of silently doing nothing.
- Rapidly changing the selected file stops obsolete thumbnail work, reducing delayed clicks and unnecessary CPU or disk activity.
- Existing tab, pane, location, search, sorting, file operations, and archive navigation behavior remains unchanged.

## Managed Temporary Artifacts

`ArchiveBrowsing` will return a managed artifact instead of a bare URL for temporary extraction. The artifact contains only the information needed to use and safely release the extraction:

```swift
public struct TemporaryArchiveArtifact: Equatable, Sendable {
    public let url: URL
    public let ownedDirectoryURL: URL
    public let identifier: UUID
}
```

Each extraction receives a unique directory below the canonical MyMacFinder archive-preview root. The service records the directory identity at creation time. Cleanup is allowed only when all of the following remain true:

- The directory is an immediate managed descendant of the canonical preview root.
- Its UUID matches the artifact identifier.
- Its filesystem identity still matches the directory created by MyMacFinder when identity information is available.
- The target is not a symlink and canonicalization does not escape the managed root.

Cleanup removes the exact owned directory, not the shared preview root and not the original archive or user file.

If extraction throws or is cancelled after creating an owned directory, the service removes that partial directory before rethrowing the original error. ZIPFoundation extraction receives a `Progress` object whose cancellation is synchronized with Swift task cancellation.

## Quick Look Session Ownership

Quick Look preview preparation is treated as one session:

1. Resolve normal filesystem URLs without ownership.
2. Extract archive entries as managed artifacts.
3. If any item fails or the task is cancelled, release all managed artifacts already created for that session in reverse order.
4. Hand the preview URLs and managed artifacts to `QuickLookPreviewService` only after the full list is ready.

`QuickLookPreviewService` owns the artifacts while the panel displays that session. It releases the previous session when previews are replaced and releases the current session when the panel closes. A failed panel presentation also releases the prepared session.

Preview preparation must not start when no Quick Look service is configured.

## External Application Ownership

Opening an extracted ZIP entry in another application has a different lifetime because MyMacFinder cannot know when the other application has finished reading it.

- `ExternalAppLauncher.openDefault` returns success or throws an explicit error when `NSWorkspace.open` returns `false`.
- If opening fails, the managed extraction is released immediately.
- If opening succeeds, the artifact is recorded in a small registry with its creation date and safe ownership metadata.
- At application startup, registered artifacts older than 24 hours are validated and removed.
- Active, unexpired artifacts remain untouched.
- Missing artifacts are removed from the registry without treating that as an application error.
- Corrupt registry data is preserved for diagnosis rather than decoded as an empty list that could overwrite recoverable state.

Cleanup is opportunistic on launch; no persistent background timer is required.

## Thumbnail Cancellation And Fallback Icons

`FilePreviewThumbnailLoader` will retain the `QLThumbnailGenerator.Request` associated with the current asynchronous load. Swift task cancellation will call the generator cancellation API before the task completes. Completion from a cancelled or superseded request cannot publish an image for the new selection.

When no thumbnail is available, the preview uses the existing metadata-based icon resolver. It does not call `NSWorkspace.icon(forFile:)` from the SwiftUI render path, avoiding a synchronous filesystem or network-volume lookup during selection.

## Error Handling

- Cancellation remains `CancellationError` and does not create a visible failure banner.
- Extraction and cleanup errors retain the original operation context.
- If an operation fails and cleanup also fails, the user-visible error includes both the original failure and the exact managed paths that could not be cleaned.
- Default-open failure is reported through the existing Explorer error presentation.
- Cleanup never removes a path that fails ownership validation; it reports or records the orphan instead.

## Testing Strategy

All file-changing tests create a UUID-named directory under `FileManager.default.temporaryDirectory` and remove only that exact directory during teardown.

Automated tests cover:

- Successful managed extraction and explicit release.
- Partial extraction failure and cancellation cleanup.
- Multi-item Quick Look rollback when a later extraction fails.
- Quick Look replacement, close, and presentation-failure cleanup callbacks.
- No extraction when Quick Look is unavailable.
- Successful external open registration.
- Failed external open immediate cleanup and visible error propagation.
- The 24-hour cleanup boundary, missing files, unexpired files, and ownership-validation rejection.
- Corrupt external-open registry preservation.
- Thumbnail generator cancellation and stale completion rejection through an injectable boundary.
- Metadata fallback icon behavior without path-based workspace lookup.
- Existing tab, pane, location, search scope, ordinary query, explicit tag query, sorting, and selection context remain unchanged by preview completion.

Manual QA covers:

- Quick Look of normal files and ZIP entries.
- Closing and replacing the Quick Look panel.
- Rapidly selecting large images, PDFs, videos, and archive entries.
- Opening a ZIP entry in its default application.
- A simulated or test-injected default-open failure.
- Relaunch cleanup of an expired QA artifact in an isolated temporary root.
- Verification that no user file, original archive, or unrelated temporary file is removed.

## Acceptance Criteria

- Quick Look archive artifacts do not remain after panel close, replacement, preparation failure, or cancellation.
- External-open artifacts remain available for 24 hours and are safely removed on a later launch after expiry.
- Cleanup can target only directories created and still owned by MyMacFinder.
- Opening a file with no working default application produces a visible error.
- Rapid selection changes cancel obsolete thumbnail work and cannot publish stale previews.
- Existing browsing and search context is unchanged by preview work.
- The full XCTest suite, warnings-as-errors build, release app build, code-signature verification, packaging, and running-app smoke test complete successfully before release installation.
