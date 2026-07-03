# Startup Items Implementation Plan

## Goal

Move `Startup Items` from roadmap placeholder to a working current-release feature that audits macOS launch agents/daemons and safely disables or re-enables user-owned LaunchAgent plists.

## Scope

- Scan:
  - `~/Library/LaunchAgents`
  - `/Library/LaunchAgents`
  - `/Library/LaunchDaemons`
- Parse plist fields:
  - `Label`
  - `Program`
  - `ProgramArguments`
  - `RunAtLoad`
  - `KeepAlive`
  - `StartInterval`
  - `StartCalendarInterval`
  - `Disabled`
- Classify scope:
  - user LaunchAgent
  - global LaunchAgent
  - global LaunchDaemon
- Show state:
  - enabled
  - disabled by plist flag or `.plist.mymacclean-disabled` rename
  - read-only for system-wide locations
  - missing target when the executable path is absent
- Actions:
  - disable user LaunchAgent by renaming `name.plist` to `name.plist.mymacclean-disabled`
  - enable user LaunchAgent by renaming `name.plist.mymacclean-disabled` back to `name.plist`

## Non-Goals

- Do not delete startup plist files.
- Do not edit plist contents.
- Do not call `launchctl`.
- Do not change root-owned or system-wide launch items.
- Do not request administrator privileges.

## Tests First

1. Core scanner tests:
   - parses launch plist fields and target path
   - recognizes disabled renamed plists
   - skips malformed plists
   - marks system-wide items read-only and detects missing targets
2. Core controller tests:
   - disables and enables a user LaunchAgent by renaming only
   - refuses global LaunchAgents and LaunchDaemons
3. App support tests:
   - scans and selects visible items
   - disables/enables selected user item and refreshes state
   - keeps system item actions unavailable
4. Sidebar tests:
   - Startup Items appears under current release, not roadmap
   - primary action text is `Scan Startup Items`

## Verification

- Run `swift test`.
- Build the app package.
- Run `scripts/create-dmg.sh`.
- Verify the built app signature with `codesign --verify --deep --strict`.
- Manually launch the app and exercise:
  - Applications refresh/selection
  - Orphan Files scan placeholder/result path
  - Large Files scan
  - Developer Cache scan
  - Startup Items scan
  - disable/re-enable of a disposable user LaunchAgent fixture
