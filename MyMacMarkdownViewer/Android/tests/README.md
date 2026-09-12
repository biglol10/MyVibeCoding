# Android Markdown Reader QA

This is a personal, read-only QA setup for the Android Markdown reader. The fixture set exercises UTF-8 with a BOM, Korean headings and paragraphs, nested lists, checklists, tables, code, math, Mermaid, relative Markdown links, a PNG, a long filename, script-looking literal HTML, and an `example.invalid` remote image URL.

Remote images are opt-in. The fixture URL must not cause outside network access during local QA. The script pushes only to the isolated emulator directory `/sdcard/Documents/MarkdownReader-QA`; it does not install an APK.

Run from the repository root:

```sh
ANDROID_SDK_ROOT="$HOME/Library/Android/sdk" Android/tests/emulator-setup.sh
```

The script creates or reuses only `MarkdownReader_QA`, using the installed API 35 Google APIs arm64-v8a image. It reserves emulator serial `emulator-5580` and TCP port 5580, launches headless with no audio and no boot animation, waits for `sys.boot_completed=1`, writes original fixture SHA-256 values to `Android/tests/fixtures/android-fixture-hashes.json`, and pushes the fixtures. A live process may be inspected with `pgrep -af 'emulator.*MarkdownReader_QA'`; do not target existing `OtFit_*` AVDs or a connected physical device.

For read-only verification, compare the opened document and its files against the JSON hashes after exercising navigation, links, and rendering. An unchanged hash confirms the fixture file bytes stayed unchanged; it does not prove the app UI itself is read-only.

## 1.1.1 regression coverage

`node Android/tests/reader-settings.mjs` verifies the one-time Night migration, subsequent user choices, typography preservation, native theme event, folder retry after error, and phone layout. Build reader assets before running it.

`Android/app/src/androidTest/` contains five runtime SAF query regressions with a test-only ContentProvider. `:app:assembleDebugAndroidTest` builds it. For final-release verification, the test APK was signed with the same existing personal certificate, installed on emulator-5580, then run with `am instrument -w -e class com.personal.markdownreader.SafListChildrenTest com.personal.markdownreader.test/android.test.InstrumentationTestRunner`. Do not install debug app variants over a user installation or print signing credentials. No test provider or test library is included in the release APK.

The final release was updated in place on emulator-5580. The native picker selected `/sdcard/Download/MarkdownReader-QA-111`; Markdown files, nested folders, nested document opening, Night system bars and original fixture hashes were checked. See `docs/android-1.1.1-validation.json` for exact evidence and device limits.
