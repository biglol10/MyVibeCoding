# MyMacClean

MyMacClean is a personal macOS cleaner and uninstaller built as a native SwiftUI
app. It is designed for review-first cleanup, not one-click system cleaning.

The app focuses on five daily-use cleanup areas:

- Applications: uninstall apps and selected related files.
- Orphan Files: find leftovers from apps that are no longer installed.
- Large Files: review large user files before moving anything to Trash.
- Developer Cache: clean regenerable developer caches after manual review.
- Startup Items: audit LaunchAgents and LaunchDaemons, and safely disable user
  LaunchAgents.

## Download

- macOS personal/test build zip: [MyMacClean-test-build.zip](https://github.com/biglol10/MyVibeCoding/raw/main/downloads/MyMacClean/MyMacClean-test-build.zip)

The zip is an ad-hoc signed personal build, not an Apple-notarized public
release. After unzipping, use the included `Install MyMacClean.command` from
Finder to remove quarantine, copy the app to `/Applications`, verify the local
signature, and open the installed app.

## Safety Model

MyMacClean is intentionally conservative.

- Destructive actions require explicit selection.
- Files are moved to Trash by default.
- Applications and Orphan Files can use permanent deletion only as an explicit
  opt-in in the confirmation sheet.
- Large Files and Developer Cache cleanup are Trash-only in the current app.
- Confirmation uses `DELETE`.
- Protected paths are checked again at execution time.
- User documents, Desktop, Downloads, iCloud document roots, media folders,
  system paths, and the running MyMacClean app bundle are protected for
  app-related cleanup.
- Symlink targets are resolved before deletion decisions.
- Cleanup receipts are recorded for destructive attempts.
- If Full Disk Access appears to be missing at launch, MyMacClean shows a
  permission prompt that opens System Settings directly to Full Disk Access.
- Permission-related deletion failures show a toast action that opens Full Disk
  Access settings.
- If macOS rejects the standard Trash API for an app bundle, MyMacClean retries
  through Finder. macOS may ask for permission to let MyMacClean control Finder;
  this is used only to move the selected item to Trash.
- Before a `/Applications` app bundle cleanup can request Finder access,
  MyMacClean shows its own explanation dialog and lets you cancel.
- Startup item management does not edit plist contents, does not call
  `launchctl`, and does not modify system-wide LaunchAgents or LaunchDaemons.
- Disabling a startup item renames the plist only. If the agent is already
  loaded, it may keep running until the next login or restart.

## Current Features

### Applications

- Discovers installed apps.
- Filters and sorts app list.
- Scans the selected app bundle and related Library files.
- Shows match evidence and safety level for each candidate.
- Blocks deletion of running apps and protected paths.
- Moves selected items to Trash by default.
- Supports permanent deletion and force-delete options only after explicit
  confirmation.
- Refreshes the app list and clears stale details after deletion.

### Orphan Files

- Scans known user Library cleanup roots.
- Groups leftovers by inferred bundle identifier.
- Excludes currently installed apps and the running MyMacClean bundle.
- Requires manual selection before cleanup.
- Moves selected leftovers to Trash by default.
- Supports permanent deletion and force-delete options only after explicit
  confirmation.
- Records cleanup receipts.

### Large Files

- Finds large files for manual review.
- Scans top-level files in `~/Downloads` by default.
- Uses a 500 MB minimum size threshold.
- Does not auto-select results.
- Excludes system roots and package internals.
- Sorts results by size descending.
- Supports reveal/copy-path and selected-file cleanup.
- Moves selected large files to Trash only.

### Developer Cache

- Detects common developer cache locations such as Xcode, SwiftPM, Node,
  CocoaPods, Gradle, and related cache roots.
- Calculates reclaimable size.
- Separates safer caches from review-only targets.
- Selects Safe cache targets automatically; Review targets require manual
  selection.
- Shows Docker storage as read-only when the Docker data directory exists.
- Blocks DerivedData cleanup while Xcode is running.
- Reuses the same deletion, verification, and receipt pipeline.
- Moves selected deletable caches to Trash only.

### Startup Items

- Scans:
  - `~/Library/LaunchAgents`
  - `/Library/LaunchAgents`
  - `/Library/LaunchDaemons`
- Parses common launchd plist fields such as `Label`, `Program`,
  `ProgramArguments`, `RunAtLoad`, `KeepAlive`, `StartInterval`,
  `StartCalendarInterval`, and `Disabled`.
- Shows enabled/disabled state, owner evidence, read-only status, and missing
  targets.
- User LaunchAgents can be disabled by renaming:
  - `name.plist` -> `name.plist.mymacclean-disabled`
- Disabled user LaunchAgents can be enabled by renaming them back.
- System-wide items are read-only.
- MyMacClean does not call `launchctl`; already loaded agents may continue
  until the next login or restart.

## Install on Another Mac

This app is for personal use and is ad-hoc signed, not Apple-notarized. That
means another Mac may show a Gatekeeper warning such as "damaged and can't be
opened" or offer to move the app to Trash.

Recommended personal install flow from this repository:

1. Download `MyMacClean-test-build.zip` from the link above, or build it locally:

   ```bash
   ./scripts/build-app-bundle.sh
   ```

2. Unzip the package.

3. Open `Install MyMacClean.command` from Finder. If macOS blocks the script,
   right-click it and choose Open.

4. The installer removes quarantine, copies the app to `/Applications`, verifies
   the installed app, and opens it.

5. Grant Full Disk Access:

   ```text
   System Settings -> Privacy & Security -> Full Disk Access -> add MyMacClean.app
   ```

   If MyMacClean detects missing access at launch, it shows an in-app prompt.
   Choose `Open System Settings`, enable `MyMacClean.app` under Full Disk
   Access, then restart the app.

Full Disk Access is important. Without it, scans can miss files or deletion can
fail for paths under protected Library locations.

## If Deletion Fails

MyMacClean records failed deletion attempts in Delete History. Open the failed
record and expand `Error Logs` to see the exact path and macOS error.

Common fixes:

1. Quit the app and its helpers first. If the app is still running, macOS may
   refuse to move its bundle or support folders.
2. Grant Full Disk Access to `/Applications/MyMacClean.app`, then reopen
   MyMacClean and retry. If the failure toast shows `Open Full Disk Access
   Settings`, use that button to jump to the correct settings page.
3. If MyMacClean shows `Finder Permission May Be Needed`, choose
   `Continue and Request Finder Permission` only if you want to proceed with
   that deletion. macOS may then ask whether MyMacClean can control Finder;
   allow it. This is a separate Automation permission used as a fallback for
   app bundles that the standard Trash API refuses.
4. Use `Reveal in Finder` or copy the failed path from the error log, then move
   that item to Trash manually. Finder may request an administrator password
   for some paths.
5. If the file is locked, retry with `Force unlock locked items`. This clears
   file locks and restores user write permission, but it cannot bypass Full
   Disk Access, SIP, or administrator-only locations.
6. For vendor updaters, menu bar helpers, or background agents, disable the
   startup item first or reboot, then retry cleanup.
7. Avoid `sudo rm -rf` unless you have verified every path in the failed log.
   MyMacClean protects broad user folders and system roots on purpose.

## Build

Build a local app bundle:

```bash
./scripts/build-app-bundle.sh
```

The package is written to:

```text
dist/MyMacClean/MyMacClean.app
dist/MyMacClean-test-build.zip
```

Build a personal DMG:

```bash
./scripts/create-dmg.sh
```

The DMG is written to:

```text
dist/MyMacClean-dev.dmg
```

Refresh the MyVibeCoding download artifact:

```bash
./scripts/build-app-bundle.sh
cp dist/MyMacClean-test-build.zip ../downloads/MyMacClean/MyMacClean-test-build.zip
```

## Test

Run the full test suite:

```bash
swift test
```

The package contains core tests for scanning, deletion planning, execution,
verification, receipts, protection policy, startup item control, large files,
developer cache, and app support view models.

## Project Structure

```text
Sources/MyMacCleanCore        Core scanning, safety, deletion, receipts
Sources/MyMacCleanAppSupport  View models and app presentation helpers
Sources/MyMacCleanApp         SwiftUI app and bundled resources
Tests                         Core and app-support tests
scripts                       Build and personal DMG scripts
dist                          Local build artifacts
docs/superpowers              Design and implementation notes
```

## Limitations

- Not notarized for public distribution.
- No privileged helper.
- No malware scanning.
- No RAM cleaning.
- No automatic background cleanup.
- No one-click broad system cleaner.
- No system LaunchAgent or LaunchDaemon modification.
- Startup item changes are reversible rename operations only and are recorded
  in Delete History as startup item changes.
- Large Files currently scans top-level files in `~/Downloads` by default.
