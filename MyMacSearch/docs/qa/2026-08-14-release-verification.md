# MyMacSearch V1 release verification — 2026-08-14

## Verified outcome

- Native SwiftUI app bundle built and ad-hoc signed as `com.biglol.MyMacSearch`, version `0.1.0` (`1`), macOS 14 minimum.
- Personal ZIP passed `unzip -tq`, strict deep codesign checks, isolated installer execution, and packaged-versus-installed executable hash comparison.
- `/Applications/MyMacSearch.app` was installed and launched. The installed first-run screen showed the recommended Desktop, Documents, and Downloads scopes, the exclusion policy, hidden-file option, Full Disk Access link, and `Start Indexing` button.
- The release check did not press `Start Indexing`, so it did not approve or begin a real scan of the user's folders.
- Isolated live UI QA separately confirmed the result table columns and immediate searches for `swift` and `ext:pdf` against a synthetic fixture.
- Follow-up regression QA confirmed that `Pause` immediately reaches `Paused`, a file created while paused appears after `Resume` (`8` to `9` results), and Space opens and closes Quick Look for the selected Swift file.
- The personal installer now bounds its quit AppleEvent to two seconds. Packaging and installation completed even while the previously wedged build remained unresponsive.

## Automated verification

```text
MyMacSearch: 55 tests, 1 opt-in benchmark skipped, 0 failures
MyMacFinder: 626 tests, 0 failures
MyMacSearch warning-strict build: passed
MyMacFinder warning-strict build: passed
git diff --check: passed
```

The MyMacSearch suite covers FTS5 capability failure, create/upsert/delete, generation pruning, query parsing, permission-denied scan continuation, cancellation, exclusions, symlink/package policy, FSEvents planning, real watcher start/stop lifecycle and overflow reconciliation, search race handling, paging, result actions, result-table keyboard commands, global shortcut and Quick Look behavior, release metadata, and installer safety.

The final 100,000-row metadata regression returned the exact filtered result set in 8.638 seconds including fixture creation. The most recent separate release-mode 1,000,000-row synthetic benchmark completed insertion in 173.769 seconds and measured warm search p50 8.830 ms / p95 10.371 ms with a 100-result window and a 675,659,776-byte database. The bug-fix changes did not touch the scanner, SQLite index, or search query path.

## Release artifacts and installation

```text
MyMacSearch ZIP SHA-256:
b88ec5b09fe1a6f5d71a9bd711a838006b2f256895e941c1083adb954b2798b0

MyMacSearch build / packaged / installed executable SHA-256:
33dbb27ac6e7c3ce5f444e022b18ee9891588b3968fdd449e7153d4cc713b799

MyMacFinder ZIP SHA-256:
f53948c9b6e57e4fd0467dc4bab4bae2fabac234c8d56ccb1cf8d7d214af389d

MyMacFinder build / packaged / installed executable SHA-256:
31a5393924ed01910e30059de2905dc598bce84930ac0fa140368d20c4f6f3a7
```

The updated MyMacFinder installed bundle declares `MyMacFinderSupportsExternalFolderOpen = true`. Its previous installed app was moved to the recoverable backup `/Users/biglol/.Trash/MyMacFinder.previous-20260814-1506.app` after the replacement passed strict codesign verification.

## Verification boundaries

- Both personal builds are ad-hoc signed, not Developer ID signed or notarized. `codesign --verify --deep --strict` passed; Gatekeeper `spctl --assess` rejected both as expected for these personal non-notarized builds.
- Full Disk Access behavior, inaccessible real protected folders, network volumes, and external volumes are covered by policy/unit tests but were not granted or live-scanned during release verification.
- The million-row benchmark uses generated metadata in SQLite and does not measure physical traversal of one million real file-system entries.
- The original app process that reproduced the Pause failure entered an OS-level uninterruptible exit-wait state. The fixed installed bundle was verified on disk, while live regression QA used a separate bundle identifier to avoid LaunchServices routing to that old process; a logout or restart is required to clear the stale process before ordinary installed-app launch QA can be repeated.
