# Finder Tags Manual QA

## Scope

- Finder tag metadata read/write through macOS resource values.
- Tags column in the main file table.
- Inspector tag display and Edit Tags action.
- General search and advanced Tag filter matching Finder tags.
- ZIP-backed virtual entries do not expose tag editing.
- External Finder tag changes are picked up after Refresh.

## Automated Gate

Run before manual QA:

```bash
swift test
swift build
```

## Fixture

```bash
fixture="$HOME/MyMacFinderTagsQA"
rm -rf "$fixture"
mkdir -p "$fixture/Nested"
printf "plain text\n" > "$fixture/plain.txt"
printf "tagged qa\n" > "$fixture/tagged-work.txt"
printf "nested\n" > "$fixture/Nested/readme.txt"
(cd "$fixture" && zip -qr sample.zip Nested)
xcrun swift -e 'import Foundation; let url = URL(fileURLWithPath: NSHomeDirectory() + "/MyMacFinderTagsQA/tagged-work.txt"); try (url as NSURL).setResourceValue(["Work", "Red"], forKey: URLResourceKey.tagNamesKey)'
```

## Manual Steps

1. Launch `.build/app/MyMacFinder.app`.
2. Navigate to `$HOME/MyMacFinderTagsQA`.
3. Confirm the table shows a Tags column.
4. Confirm `tagged-work.txt` shows its current Finder tags in the Tags column and inspector.
5. Click Edit Tags for `tagged-work.txt`, set `Blue, QA`, and save.
6. Confirm the table and inspector update to `Blue, QA`.
7. Type `QA` in the toolbar search field.
8. Confirm only `tagged-work.txt` remains visible.
9. Clear search, open Search Options, set Tag to `Blue`, and confirm only `tagged-work.txt` remains visible.
10. Clear the advanced Tag filter.
11. Open `sample.zip`, select the ZIP-backed `Nested` folder, and confirm the inspector does not show Edit Tags.
12. Return to the fixture folder.
13. Click Edit Tags for `tagged-work.txt`, clear the field, save, and confirm the table and inspector show no tags.
14. Externally set the tag to `External`, click Refresh, and confirm the table and inspector update.

## 2026-06-28 Result

- Automated: `swift test` passed 209 tests.
- Automated: `swift build` passed.
- Manual: latest app bundle launched from `.build/app/MyMacFinder.app`.
- Manual: fixture opened at `$HOME/MyMacFinderTagsQA`.
- Manual: Tags column rendered next to Kind without clipping the table headers.
- Manual: `tagged-work.txt` displayed `Blue, QA` in both the table and inspector after editing.
- Manual: toolbar search for `QA` matched the Finder tag and filtered the list to `tagged-work.txt`.
- Manual: advanced Search Options exposed a Tag field; filtering by `Blue` matched only `tagged-work.txt`.
- Manual: ZIP-backed `Nested` virtual folder showed no Edit Tags action in the inspector.
- Manual: saving an empty Edit Tags prompt removed all tags and showed `--` in the inspector.
- Manual: after an external tag change to `External`, Refresh updated both the table and inspector.
- Note: an older `.build/qa/MyMacFinder.app` bundle was removed during setup because Computer Use initially launched that stale bundle instead of the current `.build/app` bundle.
