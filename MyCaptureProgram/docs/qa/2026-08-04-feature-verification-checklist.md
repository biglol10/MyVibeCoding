# CaptureStudio Feature Verification Checklist

Date: 2026-08-04

This checklist describes the current checkout before the stabilization commit. It separates real UI evidence from automated or static evidence so an unexecuted live path is never reported as tested.

## Verification Legend

- **UI PASS**: exercised through the running native app and inspected on screen or in the produced media.
- **AUTO PASS**: covered by an automated test using isolated temporary data.
- **STATIC PASS**: source, bundle, script, or configuration inspected without executing the user workflow.
- **NOT LIVE**: implementation or automated coverage exists, but this machine could not safely exercise the real path.
- **NOT IMPLEMENTED**: deliberately not part of the current product surface.

## Environment And Isolation

- Git root: `/Users/biglol/Desktop/practice/MyCaptureProgram`
- Baseline HEAD: `96afc14be43cf0589e4257f7ef7b400d2d3969c0`
- Branch: `master`
- Host: macOS 15.3.2, Apple M1 Pro, one built-in 3456 x 2234 Retina display
- Toolchain: Apple Swift 6.1.2, Xcode 16.4
- UI app: a temporary app bundle and temporary Preferences/output folders under `/tmp`
- Actual Desktop, Documents, installed `/Applications/CaptureStudio.app`, and TCC grants were not modified

## 1. App Shell And Primary Workflow

| Check | Result | Evidence / Boundary |
|---|---|---|
| Native app launches and main window renders | UI PASS | Temporary `.app` launched; compact Capture, Record, Options, Settings, Guide, and History controls were visible. |
| Main window remains compact before a result exists | UI PASS + AUTO PASS | Verified visually and by `MainWindowPresentationTests`. |
| Capture and Record are one-click primary actions | UI PASS | Both buttons started selection directly. |
| Options arrow does not overlap its icon/text | UI PASS + AUTO PASS | Current fixed-width control inspected; presentation test reserves indicator room. |
| First-run guide opens as a modal | UI PASS + AUTO PASS | Guide opened and all workflow sections rendered. |
| Guide can start Capture or Record | AUTO PASS | Presentation/action wiring inspected and tested; not re-run live to avoid duplicating capture output. |
| Settings button opens and raises the Settings window repeatedly | UI PASS + AUTO PASS | Reopen behavior exercised; `SettingsWindowPresenterTests` covers existing-window and fallback paths. |
| Operation controls disable during capture/record setup | UI PASS + AUTO PASS | During recording, Capture/Options/History/editor actions disabled while Stop remained enabled. |

## 2. Screenshot Capture

| Check | Result | Evidence / Boundary |
|---|---|---|
| Rectangle selection overlay | UI PASS + AUTO PASS | Dragged a 500 x 300 point region; output was a 1000 x 600 Retina PNG. |
| Window selection | UI PASS + AUTO PASS | Selected Finder; output was exactly the 1840 x 928 window with no black margin. |
| Full-screen selection | UI PASS + AUTO PASS | Produced a 3456 x 2234 PNG matching the built-in display. |
| Crosshair/plus cursor remains active throughout selection | UI PASS + AUTO PASS | Cursor behavior observed during rectangle/window flows; reassertion, hide/restore, and reticle tests pass. |
| Escape cancels selection | UI PASS + AUTO PASS | Capture returned `Screenshot cancelled.` without replacing the current document. |
| CaptureStudio window hides before delay/selection | UI PASS + AUTO PASS | Target remained unobstructed; controller timing paths covered. |
| CaptureStudio windows are excluded from output | UI PASS + AUTO PASS | Real PNG/video inspection showed no app window; matching fails closed when the current app cannot be excluded. |
| Selected region is cropped without black canvas | UI PASS + AUTO PASS | Pixel dimensions matched selection; cropper tests cover oversized ScreenCaptureKit frames. |
| Screenshot delay: 0/3/5/10 seconds and direct 0...10 input | UI PASS + AUTO PASS | Quick presets and direct numeric control exercised/validated. |
| Duplicate Capture/Record requests serialize | AUTO PASS | Concurrent coordinator calls invoke selection once. |
| Dirty result replacement asks Save / Discard / Cancel | UI PASS + AUTO PASS | Cancel preserved the edited screenshot; async replacement revision tests pass. |
| Window geometry on displays above/below/left of primary | AUTO PASS, NOT LIVE | Coordinate fixtures pass. Only one physical display was connected, so no honest dual-monitor UI claim is made. |

## 3. Screen Recording

| Check | Result | Evidence / Boundary |
|---|---|---|
| Rectangle recording | UI PASS + AUTO PASS | Real H.264 MP4 recorded; mid-frame inspected. |
| Window recording | UI PASS + AUTO PASS | Real Finder recording was 1840 x 928, 12.1167 seconds, with no black margin or CaptureStudio window. |
| Full-screen recording | AUTO PASS, NOT LIVE | Selection/filter path covered; not recorded live in this pass. |
| Countdown runs after selection | UI PASS + AUTO PASS | 0 and 3 second settings exercised; ordering tested. |
| Configured duration auto-stops | UI PASS + AUTO PASS | Window recording stopped at configured 12 seconds; persisted values clamp to 1...120. |
| Manual Stop remains available | UI PASS + AUTO PASS | Main window restored after selection; region recording stopped from Stop control. |
| Escape cancels before recording starts | UI PASS + AUTO PASS | Returned `Recording cancelled.` and restored initial UI. |
| External/system stop returns to initial state | AUTO PASS, NOT LIVE | Service/coordinator stop lifecycle covered; macOS menu-bar `Stop Sharing` was not invoked in this isolated pass. |
| Startup failure performs complete teardown | AUTO PASS | Stream, writer, duration task, microphone path, and continuation lifecycle tests pass. |
| Repeated stop and stop-during-start are idempotent | AUTO PASS | Dedicated lifecycle tests cover both races. |
| Current app remains excluded after main window reappears | UI PASS + AUTO PASS | Real mid-recording frame showed Finder only; process-ID/bundle-ID matching is tested. |
| Standard/high bitrate selection | AUTO PASS | Bitrate calculation and settings persistence covered; subjective quality comparison was not performed. |
| Show cursor setting | AUTO PASS, NOT LIVE | Configuration is forwarded; cursor presence/absence was not visually compared in two recordings. |
| System audio | AUTO PASS, NOT LIVE | Audio configuration path is covered, but the real sample had no deliberate sound source, so audible content is unverified. |
| Microphone | AUTO PASS, NOT LIVE | Disabled in isolated Preferences; no microphone permission was requested or changed. |
| 30-second soak recording | NOT LIVE | The opt-in long test was not run because it would use a different test process/TCC identity. Short real recordings and lifecycle stress tests passed. |

## 4. Saving, Output, Clipboard, And Deletion

| Check | Result | Evidence / Boundary |
|---|---|---|
| Screenshot auto-save on/off | AUTO PASS | Both branches and auto-save failure retention covered. |
| Recording auto-save on/off | AUTO PASS | Both branches and temporary unsaved recording retention covered. |
| Manual screenshot save | UI PASS + AUTO PASS | Edited PNG saved from the result view. |
| Manual recording save | AUTO PASS | Temporary-to-configured-folder move covered. |
| Separate screenshot/recording folders | UI PASS + AUTO PASS | Settings UI changed and summaries updated; writes use the configured path. |
| Missing/unwritable folder fails instead of Desktop fallback | AUTO PASS | Result remains unsaved; no silent privacy-sensitive fallback. |
| Smart app/window filenames | UI PASS + AUTO PASS | Real files included Finder/window context. |
| Long emoji/combining filenames fit filesystem byte limit | AUTO PASS | UTF-8 component budget regression tests pass. |
| Same-second/concurrent saves never overwrite | AUTO PASS | Exclusive publication and concurrent screenshot/recording tests pass. |
| Save completion cannot overwrite newer edits/save | AUTO PASS | Revision and save-generation races covered. |
| Deleting or changing a screenshot during Save creates no stale file/history | AUTO PASS | A blocked renderer fixture deletes the document before completion; output and history stay empty. |
| Recording Save rejects a different file reused at the same path | AUTO PASS | Stored device/inode identity is checked before publication; the replacement remains untouched. |
| Copy screenshot/editor result to clipboard | AUTO PASS, NOT LIVE | Clipboard service is tested with a fake; real clipboard was not deliberately altered in this pass. |
| Reveal in Finder | AUTO PASS, NOT LIVE | Current/missing-file paths are covered; the real action was not isolated from the already-open Finder target. |
| Delete unsaved result | AUTO PASS | Clears only in-app document. |
| Delete saved result to Trash | AUTO PASS, NOT LIVE | The expected file is atomically moved into a private sibling quarantine before the Trash operation; real user Trash was intentionally not modified. |
| Replacement file at reused path is preserved | AUTO PASS | Current document and history deletion verify device/inode identity. |
| Trash race/failure recovery | AUTO PASS | A replacement created after identity validation is restored untouched; if Trash fails while the public path is occupied, the owned file is recovered under a visible collision-free name. |
| Hard-link/copy-fallback publication removes only the expected source | AUTO PASS | Both paths validate device/inode identity; deterministic source-removal and final-destination race fixtures preserve externally replaced files. |
| Source cleanup failure after publication | AUTO PASS | A completed hard-link or copy destination remains valid; the quarantined source is restored when cleanup fails instead of rolling back both visible files. |
| Copy fallback never exposes a partial final file | AUTO PASS, NOT LIVE cross-volume | A blocked chunk-copy fixture keeps the final path absent until full write and `fsync`; no second mounted volume was used to trigger a real `EXDEV` in this pass. |
| Large recording moves do not block the main UI thread | AUTO PASS | Async file-output test observes I/O off the main thread; capture/result controls remain disabled until completion. |
| Recording/export temporary files are private and cleaned | AUTO PASS | Session-owned workspaces, failure cleanup, and external replacement preservation covered. |

## 5. Screenshot Editor

| Check | Result | Evidence / Boundary |
|---|---|---|
| Select and move layers | AUTO PASS | Geometry and undo restoration covered. |
| Pen/freehand | UI PASS + AUTO PASS | Drew on left side; displayed/saved line stayed at the dragged position. |
| Highlighter | AUTO PASS | Editor creation, preview alignment, and rendered top-left coordinates covered. |
| Arrow with arrowhead | AUTO PASS | Preview and PNG renderer both verify shaft and arrowhead. |
| Rectangle | AUTO PASS | Layer creation, movement, preview alignment, and PNG output covered. |
| Ellipse | AUTO PASS | Preview alignment and asymmetric PNG placement covered. |
| Text | AUTO PASS | Creation, editing, font size, preview, and asymmetric PNG placement covered. |
| Solid redaction | AUTO PASS | Preview and PNG output use matching top-left coordinates. |
| Blur renderer | AUTO PASS, NOT IMPLEMENTED in UI | Internal renderer has a non-uniform pixel test; no user-facing blur mode is claimed. |
| Width/text-size inspector | UI PASS + AUTO PASS | Controls change according to selected tool/layer without layout shifting. |
| Undo/redo | UI PASS + AUTO PASS | Undo after save removed the layer and restored the original preview. |
| Save/Copy flatten once without baking duplicate layers | UI PASS + AUTO PASS | Save preserves immutable base/layers; undo/delete works after save. |
| Preview-to-output coordinate consistency | UI PASS + AUTO PASS | Live pen check plus asymmetric pixel and letterboxing snapshot tests. |

## 6. OCR And Quick Redact

| Check | Result | Evidence / Boundary |
|---|---|---|
| Vision OCR extraction | UI PASS + AUTO PASS | Finder text extracted in the running app; OCR model/service tests pass. |
| Copy OCR text | AUTO PASS, NOT LIVE | Fake clipboard path covered. |
| Quick Redact detects email/phone/URL/token/long number | AUTO PASS | Pattern and integration tests pass. |
| Exact Vision range boxes cover proportional text | AUTO PASS | Uses per-range boxes; conservative full-observation fallback prevents under-cover. |
| No-match Quick Redact status | UI PASS | Real image returned `No sensitive text found.` without changing the image. |
| Positive Quick Redact result | AUTO PASS, NOT LIVE | Fixture creates editable redaction layers; no live sensitive test image was used. |
| OCR/Quick Redact cannot overwrite concurrent edits | AUTO PASS | Suspended OCR and stale-result tests pass. |
| Privacy contract | UI PASS + STATIC PASS | Guide states Save/Copy creates the redacted version; original saved file/current clipboard are not silently rewritten. |

## 7. Recording Preview And Export

| Check | Result | Evidence / Boundary |
|---|---|---|
| Saved recording plays in app | UI PASS + AUTO PASS | AVKit preview rendered and playback controls were available. |
| Trim Copy with explicit start/end | AUTO PASS | Range validation and output publication covered. |
| Blank trim end uses actual media duration | UI PASS + AUTO PASS | A 9.375-second source trimmed to 9.375 seconds even while configured duration was 5 seconds. |
| End beyond media clamps to actual end | AUTO PASS | Asset-duration resolver test passes. |
| GIF export | UI PASS + AUTO PASS | Real 960 x 575, 9.2-second, 46-frame GIF produced. |
| Failed/stale trim or GIF leaves no partial public file | AUTO PASS | Private workspace, stale-document, and source-file replacement cleanup tests pass before and after export. |

## 8. History, Presets, And Pins

| Check | Result | Evidence / Boundary |
|---|---|---|
| History persists newest-first and caps at 100 | AUTO PASS | Store tests cover order, persistence, and limit. |
| PNG history uses file thumbnails, not full PNG in UserDefaults | AUTO PASS | Thumbnail file and serialization regression test passes. |
| Search by title/app/window/file | UI PASS + AUTO PASS | Search list exercised and matching tested. |
| Open history item | AUTO PASS, NOT LIVE | Coordinator opens the item with file identity retained and asks Save / Discard / Cancel before replacing a dirty result; reentrant changes are re-authorized until the current document is stable. This exact button was not exercised live. |
| Delete one history item | AUTO PASS, NOT LIVE | Metadata/thumbnail/file identity paths covered; Trash was not modified live. |
| Clear History keeps capture files | UI PASS + AUTO PASS | UI became empty while all 13 temporary output files remained. |
| Thumbnail cleanup cannot delete an external path | AUTO PASS | Corrupt metadata fixture preserves protected external file. |
| Built-in presets | UI PASS + AUTO PASS | Quick Clipboard, Bug Recording, Document Save, and Share Safe available. |
| Presets preserve folders and recording quality | UI PASS + AUTO PASS | Bug Recording applied timing without resetting durable preferences. |
| Save and delete personal preset | UI PASS + AUTO PASS | `Personal 1` created and deleted from Options. |
| Floating screenshot pin | UI PASS + AUTO PASS | Pin opened above other windows, closed, and released service storage. |

## 9. Settings, Shortcuts, And Permissions

| Check | Result | Evidence / Boundary |
|---|---|---|
| Output tab | UI PASS + AUTO PASS | Auto-save, Finder reveal, smart names, folders, and reset controls visible/persistent. |
| Capture tab | UI PASS + AUTO PASS | Clipboard and screenshot-delay controls visible/persistent. |
| Record tab | UI PASS + AUTO PASS | Audio, cursor, countdown, duration, and quality controls visible/persistent. |
| Timing UX supports presets and direct typing | UI PASS + AUTO PASS | No repeated stepper-only interaction required; values clamp to supported ranges. |
| Shortcuts tab | UI PASS + AUTO PASS | Screenshot, recording, and Settings shortcuts customizable. |
| Duplicate shortcut validation | AUTO PASS | Duplicate binding reports the conflicting action. |
| Reset one / Reset all shortcuts | UI PASS + AUTO PASS | Controls visible; persistence/reset tests pass. |
| Global screenshot/record shortcuts register and re-register | AUTO PASS, NOT LIVE | Carbon registrar is tested with a fake; real global key combinations were not sent to avoid conflicts. |
| Advanced permissions status | UI PASS + AUTO PASS | Existing screen-recording authorization displayed as Allowed; microphone remained Off/not requested. |
| Permission failures show user-facing guidance | AUTO PASS | Preflight and actionable prompt paths covered without changing TCC. |
| Reset all settings | UI PASS + AUTO PASS | Control visible; defaults/persistence tests pass. |
| Corrupt persisted timing values | AUTO PASS | Negative/extreme values clamp before recording arithmetic. |

## 10. Distribution, CI, Accessibility, And Visual QA

| Check | Result | Evidence / Boundary |
|---|---|---|
| Required fancy app icon sizes and `.icns` | AUTO PASS | All 10 iconset sizes decoded at expected dimensions. |
| Local install builds as normal user | STATIC PASS + AUTO PASS | Script rejects whole-script sudo and limits elevation to final install. |
| Existing app replacement is transactional | STATIC PASS + AUTO PASS | Staging, backup, rollback, and LaunchServices registration verified. |
| Personal-Mac package scopes quarantine removal | STATIC PASS + AUTO PASS | Quarantine removal targets packaged app, not the entire extracted directory. The installer refuses to replace a running app instead of force-quitting unsaved work. |
| Notarized release avoids password in process arguments | STATIC PASS + AUTO PASS | Keychain profile required; Developer ID, hardened runtime, stapling, and Gatekeeper checks asserted. |
| Actual notarization | NOT LIVE | No Developer ID certificate/notary submission was used in this local QA pass. |
| GitHub Actions workflow is at repository root | STATIC PASS + AUTO PASS | `.github/workflows/ci.yml` runs `swift test` on macOS 15. |
| Shell syntax | STATIC PASS | All `.sh` and `.command` files checked with `bash -n` in final verification. |
| Accessibility names/tooltips | UI PASS | Native accessibility tree exposed primary controls and editor action names. |
| Dark appearance | UI PASS | Main, Settings, overlays, editor, history, preview, and guide inspected in dark mode. |
| Light appearance | NOT LIVE | Native semantic colors are used, but a full light-mode visual pass was not performed. |

## 11. Deliberately Unimplemented Features

The current app does not claim freeform snips, scrolling capture, audio-device selection, a color picker, print/share integrations, or Perfect Screenshot-style automatic region adjustment. The internal blur renderer is tested but not exposed as an editor mode.

## Final Verification Summary

- Debug build: PASS in isolated scratch/home/cache directories.
- Release build: PASS in isolated scratch/home/cache directories.
- Default tests: PASS, 289 executed, 11 opt-in live tests skipped, 0 failures.
- Opt-in ScreenCaptureKit XCTest targets: not run under the test process because TCC was not changed; equivalent core rectangle/window screenshot and recording flows were exercised through the temporary native app.
- Physical dual-monitor UI, a real cross-volume `EXDEV` move, microphone capture, deliberate system-audio playback, 30-second recording, light-mode visual QA, and notarization remain explicitly unverified live boundaries.
