# CaptureStudio Follow-up Hardening Verification

- Date: 2026-08-08
- Baseline: `cff4067f3a7c2d72b824de8f7371b8e22dca9de6`
- Scope: MyCaptureProgram source, tests, local/personal packaging scripts, and user-facing documentation

## Confirmed defects fixed

| Area | Confirmed defect | Resolution |
|---|---|---|
| Editor | Exactly horizontal or vertical arrows were rejected because shape validation required both width and height. | Arrow validation now uses drag distance while rectangles and ellipses retain two-dimensional validation. |
| Global shortcuts | A shortcut without Command, Option, or Control could intercept ordinary typing, including unsafe values loaded from preferences. | Unsafe edits are rejected, unsafe persisted values fall back to defaults, and Settings explains the required modifiers. |
| Recording trim | Invalid nonblank start/end values were silently treated as zero or the media end. | Trim fields now distinguish blank values from malformed, non-finite, and reversed ranges and report a user-facing error. |
| GIF export | Invalid media duration could reach unsafe frame-count conversion, and partial final intervals could be omitted. | Export planning validates finite positive values, rounds partial intervals up, and rejects unreasonable frame counts. |
| Unsaved work | Quitting could discard a dirty screenshot or temporary recording without Save / Discard / Cancel handling. | App termination now runs through the same document-safety workflow and is blocked while capture or file work is active. |
| Quit concurrency | A global capture shortcut could start new work while the quit decision was awaiting user input, and termination did not recheck activity before approval. | Termination preparation now blocks new capture/record entry and rechecks active work after the decision. |
| Temporary recordings | A successful trim of an unsaved recording could leave the original temporary MP4 behind. | Owned temporary recordings are removed through identity-checked atomic quarantine after successful replacement. |
| Install scripts | macOS Bash with `set -u` failed when expanding an empty privilege array. | Both installers use an explicit privileged-command dispatcher compatible with the system Bash. |
| Personal package | Building a personal zip could register its staging app with LaunchServices. | Personal packaging suppresses registration for the temporary bundle while normal installation still registers the final app. |

## Verification evidence

Project-controlled build, test, preferences, app-data, and package output paths were isolated under a unique `/tmp` directory. The real Desktop, Documents, installed app, clipboard, and TCC settings were not used.

| Check | Result |
|---|---|
| Default `swift test` | 312 executed, 11 skipped, 0 failures |
| Debug `swift build` | Passed from a fresh isolated scratch path |
| Release `swift build -c release` | Passed from a fresh isolated scratch path |
| Shell syntax | All three repository `.sh` files passed `bash -n` |
| macOS Bash compatibility | Privileged-command helpers ran successfully under `/bin/bash` with `set -euo pipefail` |
| Personal package | Zip created in an isolated copy; archive integrity, generated installer syntax, Info.plist, and strict ad-hoc signature verification passed |
| Safe UI smoke test | Test bundle launched; guide, main window, Settings, Shortcuts, reset, quick-options menu, Escape dismissal, and clean quit worked |

## Verification boundaries

- The 11 skipped tests require live ScreenCaptureKit access. This pass did not change or rely on the user's TCC permissions, so real screenshot/recording, microphone capture, and multi-display selection were not repeated.
- A Developer ID identity and notarization credentials were not used. The notarized public-release path was inspected and unit-tested, not submitted to Apple.
- The safe UI smoke test intentionally avoided Capture and Record because those actions would use live screen/clipboard/output resources.
