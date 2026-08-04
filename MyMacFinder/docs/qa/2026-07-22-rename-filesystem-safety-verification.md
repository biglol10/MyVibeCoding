# Rename and Filesystem Safety Verification - 2026-07-22

## Scope

This verification covers inline rename, recursive search context isolation, pane load races, transactional Trash rollback, canonical path and filesystem identity checks, case-only rename, compound Undo, and the related copy/ZIP rollback hardening.

The current worktree was used as the source of truth. Existing user files and the user's existing Trash contents were not used as test fixtures. All mutation tests used UUID-named paths under `FileManager.default.temporaryDirectory`, and Trash behavior in XCTest was injected through simulated Trash directories.

## Toolchain

| Check | Result |
|---|---|
| `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` |
| `xcodebuild -version` | Xcode 16.4, build 16F6 |
| `xcrun --find xctest` | `/Applications/Xcode.app/Contents/Developer/usr/bin/xctest` |

## Automated Verification

| Command | Result |
|---|---|
| `swift build -Xswiftc -warnings-as-errors` | Passed |
| `swift test --enable-code-coverage` | 492 tests, 0 failures |
| Rename/search/pane/drop focused suites | 107 tests, 0 failures |
| File operation/ZIP/Undo focused suites | 105 tests, 0 failures |
| Independent reviewer focused suites | 225 tests, 0 failures |
| `git diff --check` | Passed |
| `./scripts/build_app.sh --configuration release` | Passed |
| `codesign --verify --deep --strict --verbose=2 build/MyMacFinder.app` | Passed |
| `./scripts/verify-app-icon.sh` | Passed |
| `./scripts/package_personal.sh` | Passed |
| `/usr/bin/unzip -tq dist/MyMacFinder-personal-mac.zip` | Passed |

The production diff was also scanned for newly added `try!`, `as!`, `fatalError`, empty `catch`, and error-hiding `try?` patterns. None were found. Pane/search commits were reviewed for stale index or context use after `await`; filesystem rollback paths were reviewed for symlink canonicalization and unrelated-file deletion hazards.

## Independent Review

A separate read-only reviewer inspected the complete worktree and untracked additions with emphasis on data loss, symlink and hard-link confusion, stale async mutation, case-only rename, Trash/copy/ZIP rollback, and compound Undo. No Critical or Important finding remained after the final review.

## Isolated App Smoke Test

- QA ID: `A4BA2419-4117-4E5D-A55B-2FF064251B91`
- QA bundle ID: `com.biglol.MyMacFinder.qa.a4ba241941174e5da55b2ff064251b91`
- QA root: `/var/folders/6_/0tkhlljj7jbfp_07hkxv0k900000gn/T/MyMacFinder-QA-A4BA2419-4117-4E5D-A55B-2FF064251B91`
- Launch PID: `17268`
- Launch executable: the QA bundle's `Contents/MacOS/MyMacFinder`

Verified through the running AppKit/SwiftUI UI:

- Existing file rename through F2: Escape preserved the old name; Return committed the new name.
- Existing folder rename through F2 and Return.
- New folder creation through Command-Shift-N immediately entered inline rename and committed with Return.
- Context-menu Rename exposed the inline editor; the same item menu exposed Delete.
- `report.txt` to `REPORT.txt` case-only rename changed the physical directory entry; Command-Z restored the exact `report.txt` spelling.
- Dual pane activation, recursive `Report` search, active-pane switching, and return to single pane completed without stale results, array traps, or a crash.
- Copying `SourceGuard` into `AliasIntoSource`, a symlink to the source itself, was rejected with `Cannot copy a folder into itself.` No nested output was created.
- Duplicate created `renamed-file copy.txt`; Command-Z removed only the duplicate.
- A failed operation retained its failure banner, while the successful duplicate banner dismissed automatically.
- The process remained responsive and running after all flows.

The QA app was quit normally. The exact QA root above was inspected for unexpected rollback/quarantine leftovers and then removed; post-cleanup existence check returned `removed`.

Multi-item Trash cancellation and rollback failure cannot use the production UI without touching the real Trash. Those flows were therefore verified only through injected simulated-Trash XCTest cases, not reported as UI-passed.

## Installation Verification

- Install staging ID: `FF96D644-8978-4358-8B13-DB526CD437B4`
- Build executable SHA-256: `ae11db91d2aa4f7113d64391b8bb0f9c49eb9be516e9f67980ae3424a44201ae`
- Staging executable SHA-256: same as build
- Installed executable SHA-256: same as build
- Installed path: `/Applications/MyMacFinder.app`
- Installed launch PID: `33399`
- Installed executable path: `/Applications/MyMacFinder.app/Contents/MacOS/MyMacFinder`
- Installed strict codesign verification: passed

The previous installation was moved to `/Applications/MyMacFinder.app.backup-FF96D644-8978-4358-8B13-DB526CD437B4` before replacement. After the new app passed hash, signature, path, PID, and immediate-crash checks, the backup was moved to the recoverable Trash path `/Users/biglol/.Trash/MyMacFinder.app.backup-FF96D644-8978-4358-8B13-DB526CD437B4`. The install staging directory was then removed.

## Remaining Follow-up Risks

- Quick Look temporary ZIP extraction lifecycle cleanup in `ArchiveBrowsingService` remains a separate follow-up.
- Stale security-scoped bookmark refresh failure cleanup and corrupt bookmark-store recovery need a separate audit.
- Public distribution still needs Developer ID signing, notarization, and entitlement validation.
