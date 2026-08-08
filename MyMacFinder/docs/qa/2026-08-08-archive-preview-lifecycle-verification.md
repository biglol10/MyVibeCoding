# Archive Preview Lifecycle Verification

- Verification date: 2026-08-09 (Asia/Seoul)
- Branch: `master`
- Implementation HEAD before documentation: `82b543392134fc94b8cff6f20b60c2dfef7270b4`
- Result: PASS with explicit manual-verification boundaries
- Production/test edits during this run: none
- Push: not performed

## Fresh Automated Gate

All requested commands were run from the clean implementation HEAD and exited `0`.

```text
xcode-select -p
/Applications/Xcode.app/Contents/Developer

xcodebuild -version
Xcode 16.4
Build version 16F6

xcrun --find xctest
/Applications/Xcode.app/Contents/Developer/usr/bin/xctest

swift build -Xswiftc -warnings-as-errors
Build complete

swift test --enable-code-coverage
Executed 591 tests, with 0 failures (0 unexpected)

git diff --check
no output
```

The Swift Testing runner contained 0 additional tests. Fresh HEAD/status checks showed clean `master` at the exact implementation commit before documentation edits.

## Lifecycle Safety Review

The current lifecycle implementation and final edge review were reread before release. No automated or live Critical/Important issue appeared.

- Cleanup is descriptor-anchored and no-follow. It uses private owner/output modes, `openat`, `fstatat(..., AT_SYMLINK_NOFOLLOW)`, `renameatx_np(..., RENAME_EXCL)`, `unlinkat`, close-on-exec descriptors, checked writes, and `EINTR` loops.
- Cleanup authorizes an empty validated UUID owner or exactly one expected output leaf. Unexpected entries, replacement identities, symlinks, or extra directories are preserved rather than recursively removed.
- Pending-cleanup and retention records persist owner and output device, inode, generation, and mode. Output and owner pathname identities are checked again immediately before Quick Look/default-open handoff.
- `MyMacFinder.pendingArchiveTemporaryArtifactCleanup` and `MyMacFinder.retainedArchiveTemporaryArtifacts` are independent registries. Corrupt/duplicate or unavailable state in one phase is preserved and does not silently overwrite the other.
- Archive extraction and Explorer handoff check parent cancellation before and after extraction and immediately before presentation/launch. Cancellation releases in reverse order and does not present a cancellation banner.
- ZIP Quick Look records exact cleanup authority durably before panel presentation. A process exit can therefore leave a pending record and owner for exact startup retry.

The lifecycle source scan found no path-based `removeItem`, path-destination archive extraction, `try!`, `as!`, `fatalError`, empty catch, or `NSWorkspace.icon(forFile:)` use in the reviewed scope.

## Fresh Release Artifacts

```text
./scripts/build_app.sh --configuration release
build/MyMacFinder.app generated and ad-hoc signed

codesign --verify --deep --strict --verbose=2 build/MyMacFinder.app
valid on disk; satisfies its Designated Requirement

./scripts/package_personal.sh
dist/MyMacFinder-personal-mac.zip created

codesign --verify --deep --strict --verbose=2 dist/MyMacFinder-personal-mac/MyMacFinder.app
valid on disk; satisfies its Designated Requirement

/usr/bin/unzip -tq dist/MyMacFinder-personal-mac.zip
No errors detected in compressed data
```

Hashing used `LC_ALL=C LANG=C`.

```text
64cb9376df0e1ca922a11c6cfbb1469563a92a3a873370fba244d43883ba024f  build/MyMacFinder.app/Contents/MacOS/MyMacFinder
64cb9376df0e1ca922a11c6cfbb1469563a92a3a873370fba244d43883ba024f  dist/MyMacFinder-personal-mac/MyMacFinder.app/Contents/MacOS/MyMacFinder
9daf4f28fe0dc5797165f989ef31e539d495d426e90952b14cca3e49a0f6075c  dist/MyMacFinder-personal-mac.zip
```

## Isolated Live QA

The QA root was a new bare UUID child directly below the system temporary directory:

```text
/var/folders/6_/0tkhlljj7jbfp_07hkxv0k900000gn/T/FC4CF3D7-DD61-4897-9B17-28F2B9D6A764
```

The copied release app used bundle/defaults ID `com.biglol.MyMacFinder.FinalQA.FC4CF3D7`, was ad-hoc signed, and passed strict signature verification. Fixtures and the app copy remained under this root. No user file or real Trash item was used as a QA fixture.

Baseline and post-QA hashes matched exactly:

```text
23091f558b8ac03fb9cd7e6565abb388450000e1e91c6959964933109652be8a  preview-fixture.txt
c4f9352e40fa8444a90e13bb3d880c8a964b350cd94b46fa60dfd110443ec2b8  preview-fixture.png
17101a234a1bbd84dce94fa5b2b3d90874535caf628855758aaa8b64f0c13ce9  preview-fixture.pdf
aba1a3cd8daca24f0ad188425e1110cb8f285c43c7c2c3dc6e14d3d1cbe6ee14  preview-fixtures.zip
6a74c5ed99cc01989928b2640ecff44e81d2e95229b7936f6b0a5547220fb26a  unrelated-sentinel.txt
```

### Actually Performed GUI Checks

- Opened and closed a real normal-file Quick Look panel for `preview-fixture.txt`.
- Clicked PDF -> PNG -> text in rapid order. The final selected row and inspector content were the text fixture, and exact QA PID `89113` remained running without a crash or visible error.
- Opened ZIP entry Quick Look. The real panel displayed `MyMacFinder Quick Look lifecycle fixture`.
- While the ZIP panel was open, exact pending owner `4B7024C3-A7E9-4C2D-8B94-855722C34733` and its output existed, the pending registry contained that exact owner, retention was absent, and extracted/source hashes matched.
- Clicked the actual Quick Look panel close button. The main QA window returned and PID `89113` still resolved to the canonical QA executable. The exact owner and pending record were absent at condition poll `0`.
- Clicked the actual ZIP-entry `Open` control. TextEdit displayed the expected text from exact URL owner `AC390B71-CA64-4FD0-B1C4-19EE74D3D4B9`. The retention record existed, pending cleanup was absent, and output/source hashes matched.

### Expired Retention Relaunch

Only the isolated QA retention record was changed, setting its `openedAt` to `0`. PID `89113` was terminated only after exact executable-path equality. Relaunch used the same QA bundle and defaults domain as PID `92566`.

Exact retained owner `AC390B71-CA64-4FD0-B1C4-19EE74D3D4B9` and its retention record were both absent at condition poll `2`. No broad temporary-directory scan or deletion was used.

### Durable Process-Exit Recovery

With a second real ZIP Quick Look panel open and displaying the fixture:

1. Exact pending owner `DFD94B4A-0668-4105-81B2-E4D63420D2CF`, output, and one pending record existed; retention was absent.
2. PID `92566` was terminated only after its command exactly matched the QA executable.
3. After process exit, that exact owner and pending record still existed.
4. The same QA bundle/defaults domain relaunched as PID `93349`.
5. Condition polling only the recorded owner and key found the exact owner and pending record gone at poll `2`.

This is direct live evidence of durable Quick Look process-exit recovery, not only recreated-store unit-test evidence.

## MANUAL VERIFICATION REQUIRED

These flows retain automated coverage but were not claimed as live passes:

- Quick Look panel replacement while preserving an observable first panel.
- Tab/pane/search/selection mutation during an in-flight archive extraction.
- A genuinely slow large-file generator cancellation. The live rapid-click check proves final state/no crash only; generator cancellation and late-completion rejection remain automated evidence.
- Injected default-open failure and cancellation-banner semantics in the signed release UI.

## QA Cleanup

- Final QA PID `93349` was terminated after exact executable-path equality; absent at poll `1`.
- The exact QA defaults domain was deleted and absent at poll `0`.
- The QA app and one-level UUID root were removed only after Foundation validated the system-temporary parent and UUID leaf.
- Exact owners `4B7024C3-A7E9-4C2D-8B94-855722C34733`, `AC390B71-CA64-4FD0-B1C4-19EE74D3D4B9`, and `DFD94B4A-0668-4105-81B2-E4D63420D2CF` were all proven absent.
- Fixture, original ZIP, source, and sentinel hashes matched before guarded root cleanup. Trash was not emptied.

## Safe Installation

- Install UUID: `B8040CE1-E821-4496-8A0B-811747EAE056`
- Previous installed executable hash: `bc18a4a05250c7c1c736557e0d36fff91ab10148bac30163a66a574e8e9be63e`
- New build/packaged/staged/installed executable hash: `64cb9376df0e1ca922a11c6cfbb1469563a92a3a873370fba244d43883ba024f`

The release was copied to a UUID staging directory on `/Applications`, strictly signature-checked, and hash-compared before replacement. Only a process whose exact command matched `/Applications/MyMacFinder.app/Contents/MacOS/MyMacFinder` was terminated. The previous bundle moved to a unique rollback path, and same-volume renames published the new bundle.

The installed app passed strict signature verification, matched both build and packaged hashes, and launched as:

```text
PID 94702
/Applications/MyMacFinder.app/Contents/MacOS/MyMacFinder
```

Rollback was armed but not needed. The previous bundle moved to `/Users/biglol/.Trash/MyMacFinder-backup-B8040CE1-E821-4496-8A0B-811747EAE056.app` without emptying Trash. The staging directory and in-Applications rollback path are absent.

## Residual Framework Limit

AppKit Quick Look and LaunchServices consume pathname URLs. A same-user process can still replace the path after MyMacFinder's final no-follow owner/output identity check but before the framework opens it. The current code prevents handoff when the final check detects a mismatch; fully eliminating the remaining kernel-level check-to-use window would require a handle-based consumer API or a different publication design.

## Evidence Boundary

Automated tests prove deterministic descriptor, identity, registry, cancellation, replacement, stale-context, and error branches. The live evidence proves only the GUI actions and process lifecycle steps explicitly listed above. The manual-required items remain manual-required and are not promoted to release-app passes.
