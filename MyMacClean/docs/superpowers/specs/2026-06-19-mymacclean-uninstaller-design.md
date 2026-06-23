# MyMacClean Uninstaller Design

Date: 2026-06-19

## Decision Summary

MyMacClean will be a native SwiftUI macOS app distributed outside the Mac App Store as a signed and notarized DMG. The long-term product goal is a CleanMyMac-class utility, but the first release will focus on one strong workflow: finding installed applications, showing all related files, and permanently deleting the selected app and its associated data after explicit review.

The approved UI direction is a premium native inspector layout: left sidebar for modules, center app list, and right inspector for selected app details and related file review. The visual tone should feel closer to Finder, System Settings, and Activity Monitor than to a flashy cleaner dashboard.

The approved deletion policy is permanent deletion, not Trash-first deletion. Because that is risky, deletion must always require a review screen, show exact paths, exclude protected user-content locations by default, and require an explicit final confirmation before calling destructive file operations.

## Research Notes

CleanMyMac positions itself as an all-in-one Mac care product covering cleanup, malware protection, performance, app management, cloud cleanup, duplicates, and disk visualization. Its current Applications module scans installed apps, groups them by criteria such as unused apps, stores, vendors, and plugins, and removes app components outside `/Applications` where macOS permits it.

AppCleaner is much narrower: it focuses on thoroughly uninstalling unwanted apps by finding small support files created around the system and deleting them. This validates that a focused uninstaller can be valuable without shipping every system-cleaning feature in the first release.

Sources used for product scope:

- CleanMyMac product overview: https://cleanmymac.com/
- CleanMyMac Applications / Uninstaller support page: https://macpaw.com/support/cleanmymac/knowledgebase/uninstaller
- CleanMyMac X Uninstaller support page: https://macpaw.com/support/cleanmymac-x/knowledgebase/uninstaller
- AppCleaner product page: https://freemacsoft.net/appcleaner/
- Macworld CleanMyMac feature grouping reference: https://www.macworld.com/article/352922/cleanmymac-x-review-macos.html

## Product Scope

### V1: Professional App Uninstaller

V1 must solve the original pain point: macOS lacks a Windows-style uninstall control panel, and dragging an app to the Trash leaves preferences, caches, support files, containers, logs, and background launch items behind.

V1 will include:

- Installed app discovery from `/Applications`, `~/Applications`, and additional user-selected folders.
- App metadata extraction from each `.app` bundle, including display name, bundle identifier, version, executable name, icon, signing information where available, install path, bundle size, and last-opened signal when available.
- Related file scanning based on bundle identifier, app display name, executable name, and known macOS library locations.
- A review panel that shows each related item, exact path, type, size, confidence, and default selection state.
- Permanent deletion after explicit confirmation.
- A deletion report stored locally so users can inspect what was removed.
- A protected-path system that prevents accidental deletion of user documents and system-critical locations.
- A high-quality SwiftUI interface matching the approved native inspector direction.

V1 will not include:

- General malware scanning.
- Duplicate file detection.
- Large file cleanup.
- System-wide cache cleanup unrelated to a selected app.
- Automatic maintenance scripts.
- Cloud cleanup.
- Mac App Store distribution.

### V2: App Management Expansion

V2 should expand the app-management surface after V1 deletion quality is reliable.

Candidate V2 features:

- Startup item and background item review.
- LaunchAgent and LaunchDaemon management with enable, disable, reveal, and delete actions.
- Leftover scanner for files belonging to apps already removed.
- App reset workflow that deletes user state while keeping the app bundle.
- App grouping by unused, large, vendor, install source, and plugin type.
- Update availability indicators if a reliable metadata source is chosen later.
- Signature and notarization visibility for app trust review.

### V3: CleanMyMac-Class Utility Roadmap

V3 can move toward the broader CleanMyMac-style product, but each module should remain separately testable and opt-in.

Candidate V3 modules:

- System cleanup for user caches, logs, browser caches, and temporary files.
- Large and old file explorer with path review before deletion.
- Duplicate file detection with hash-based confirmation.
- Disk space visualization.
- Maintenance tasks such as DNS cache flush, Spotlight reindex triggers, and app permission review.
- Privacy cleanup for browser history, downloads, and app traces, only after clear per-source consent.
- Lightweight health dashboard summarizing disk space, startup items, background agents, and cleanup opportunities.

## Architecture

The app will be organized around small services with strict boundaries:

- `AppDiscoveryService`: finds `.app` bundles and extracts metadata.
- `AppMetadataReader`: reads `Info.plist`, app icons, bundle size, version, executable name, and identifiers.
- `RelatedFileScanner`: generates candidate paths for a selected app and classifies them.
- `CandidateMatcher`: scores whether a file belongs to an app based on bundle ID, app name, executable name, parent directory, and known path pattern.
- `ProtectionPolicy`: blocks dangerous paths and marks ambiguous paths for manual selection only.
- `DeletionPlanner`: converts selected candidates into a deterministic deletion plan.
- `DeletionExecutor`: permanently deletes files and directories after final confirmation.
- `DeletionJournal`: records what was deleted, when, by which app metadata, and whether any item failed.
- `PermissionCoordinator`: handles Full Disk Access guidance and permission-related failures.
- `SwiftUI ViewModels`: expose scanner and deletion state to the UI without putting filesystem logic inside views.

The scanner and deletion services should be platform-logic modules independent of SwiftUI so they can be tested with temporary directories and fixture `.app` bundles.

## Related File Detection

The scanner will look for app-related files in known locations under the current user's home directory first:

- `~/Library/Application Support`
- `~/Library/Caches`
- `~/Library/Preferences`
- `~/Library/Saved Application State`
- `~/Library/Containers`
- `~/Library/Group Containers`
- `~/Library/Logs`
- `~/Library/HTTPStorages`
- `~/Library/WebKit`
- `~/Library/Application Scripts`
- `~/Library/LaunchAgents`

The scanner may later include system-level locations only when the app has sufficient authorization and the UI clearly marks the elevated risk:

- `/Library/Application Support`
- `/Library/Caches`
- `/Library/Preferences`
- `/Library/Logs`
- `/Library/LaunchAgents`
- `/Library/LaunchDaemons`
- `/Library/PrivilegedHelperTools`

Each candidate must be assigned:

- `path`
- `kind`, such as app bundle, cache, preferences, support data, container, launch item, log, script, or unknown
- `size`
- `matchReason`
- `confidence`, such as high, medium, or low
- `defaultSelected`
- `requiresManualReview`
- `isProtected`

High-confidence candidates can be selected by default. Medium-confidence candidates can be selected when they are inside well-known app-support folders. Low-confidence candidates must be visible but unselected by default.

## Permanent Deletion Policy

Permanent deletion is approved for this product, but it must not behave like a one-click shredder.

Required flow:

1. User selects an app.
2. App scans for related files.
3. UI shows all candidates grouped by file type and confidence.
4. User selects or deselects candidates.
5. UI shows a final confirmation sheet with total file count, total size, and exact app name.
6. User confirms destructive deletion by typing `DELETE <AppName>` or completing an equivalent explicit confirmation.
7. `DeletionExecutor` deletes files permanently with filesystem removal APIs rather than moving them to Trash.
8. `DeletionJournal` records successful and failed deletions.

The app must never permanently delete files from these protected locations as automatic related files:

- `~/Desktop`
- `~/Documents`
- `~/Downloads`
- `~/Pictures`
- `~/Movies`
- `~/Music`
- iCloud Drive user documents
- external volumes unless explicitly selected as an app scan root
- `/System`
- `/bin`
- `/sbin`
- `/usr` except safe app-specific support locations explicitly introduced in a future version
- `/private`
- `/var`

If a file in a protected location appears related to an app, it can only be shown as "protected, not removable by MyMacClean" in V1.

## Permissions

The app should operate with normal user permissions where possible. Some app leftovers may be inaccessible without Full Disk Access or administrator privileges. V1 should not silently request broad privileges at launch.

Permission behavior:

- If a path cannot be scanned, show a clear "permission required" status for that path group.
- Provide a guided Full Disk Access screen only when the user initiates a scan that needs it.
- Do not use a privileged helper in V1 unless testing proves required for the core user-level workflow.
- Avoid Mac App Store distribution because sandbox restrictions conflict with broad application cleanup.

## UI Design

The approved UI direction is "native inspector, restrained, inspection-first."

Core layout:

- Titlebar with native macOS window controls and compact toolbar actions.
- Sidebar with V1 modules and disabled roadmap modules.
- Main app table with search, segmented filters, app icon, name, bundle ID, size, last used, and related file count.
- Right inspector with selected app summary, size breakdown, grouped related files, confidence indicators, protected items, and destructive action.
- Deletion confirmation sheet with exact file count, total size, permanent deletion warning, and final confirmation control.

Visual rules:

- Use macOS material, subtle borders, neutral grays, and restrained blue accents.
- Avoid oversized marketing cards, colorful cleanup score widgets, cartoon illustrations, and dramatic gradients.
- Keep dense professional information readable.
- Treat dangerous actions with clear red styling, but only at the final action points.

## Data Model

Initial domain models:

```swift
struct InstalledApp: Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let bundleIdentifier: String?
    let version: String?
    let executableName: String?
    let bundleURL: URL
    let iconIdentifier: String?
    let bundleSize: Int64
    let lastOpenedAt: Date?
}

enum RelatedFileKind: String, Codable {
    case appBundle
    case applicationSupport
    case cache
    case preferences
    case savedState
    case container
    case groupContainer
    case log
    case httpStorage
    case webKit
    case launchAgent
    case launchDaemon
    case script
    case unknown
}

enum MatchConfidence: String, Codable {
    case high
    case medium
    case low
}

struct RelatedFileCandidate: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let kind: RelatedFileKind
    let size: Int64
    let matchReason: String
    let confidence: MatchConfidence
    let defaultSelected: Bool
    let requiresManualReview: Bool
    let isProtected: Bool
}

struct DeletionPlan: Equatable {
    let app: InstalledApp
    let candidates: [RelatedFileCandidate]
    let totalSize: Int64
    let createdAt: Date
}
```

These models can evolve during implementation, but the implementation plan should preserve their intent: filesystem logic returns structured, testable data rather than UI-specific strings.

## Testing Strategy

Testing must focus on deletion safety and scanner correctness.

Required V1 test coverage:

- App discovery finds fixture `.app` bundles in configured roots.
- Metadata reader extracts bundle identifier, display name, executable name, and version from fixture `Info.plist`.
- Related file scanner finds expected candidates for bundle ID and app name fixtures.
- Candidate matcher does not match unrelated files with similar partial names.
- Protection policy blocks user document folders and system-critical paths.
- Deletion planner includes only selected, unprotected candidates.
- Deletion executor removes files in a temporary test directory and refuses protected paths.
- Deletion journal records successes and failures.
- ViewModels expose scanning, selection, confirmation, success, and failure states.

The implementation should use test-first development for core scanner, protection, planning, and deletion logic.

## Distribution

Target distribution is a signed, notarized DMG outside the Mac App Store.

Distribution requirements:

- Bundle identifier under a project-specific reverse DNS namespace.
- Hardened runtime enabled for notarization.
- Clear onboarding for Full Disk Access when needed.
- No Mac App Store sandbox target in V1.
- Build scripts should eventually support archive, export, notarize, staple, and DMG creation.

## Risks And Mitigations

Permanent deletion is the biggest product risk. Mitigation: require path review, explicit final confirmation, structured deletion plans, protected path blocking, and deletion journals.

False-positive matching is the second biggest risk. Mitigation: confidence scoring, conservative defaults, visible match reasons, low-confidence items unselected by default, and extensive fixture tests.

macOS permissions can make scans look incomplete. Mitigation: show permission-specific states and avoid presenting partial scans as complete.

System-app removal can break macOS or fail due to restrictions. Mitigation: hide or mark Apple system apps as protected and unsupported for V1 deletion.

Cleaner-app trust is fragile. Mitigation: local-only processing, no telemetry in V1, transparent path lists, and no vague "optimize your Mac" claims.

## Implementation Milestones

1. Create a Swift package or Xcode project with testable core modules.
2. Implement app discovery and metadata extraction with fixtures.
3. Implement related file candidate scanning and matching.
4. Implement protection policy and deletion planning.
5. Implement permanent deletion executor behind confirmation-only API.
6. Implement deletion journal.
7. Build SwiftUI app list and inspector.
8. Build final confirmation and deletion result flows.
9. Add permission guidance and failure states.
10. Prepare signed DMG distribution path.

## Approved Product Choices

- Scope: V1 app uninstaller first; v2/v3 roadmap documented for later CleanMyMac-class expansion.
- Stack: native SwiftUI macOS app.
- UI: premium native inspector style.
- Deletion: permanent deletion with mandatory review and explicit final confirmation.
- Distribution: signed and notarized DMG outside the Mac App Store.
