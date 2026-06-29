# Large File Operation UX Manual QA

## Setup

Run:

```bash
QA_DIR="$HOME/MyMacFinderLargeOperationQA"
rm -rf "$QA_DIR"
mkdir -p "$QA_DIR/source" "$QA_DIR/dest"
for i in $(seq -w 1 200); do
  printf "file-$i\n" > "$QA_DIR/source/file-$i.txt"
done
./scripts/build_app.sh
open build/MyMacFinder.app
```

Navigate the app to `$QA_DIR/source`.

## Copy Progress

1. Select all generated files in `$QA_DIR/source`.
2. Run `Copy`.
3. Navigate to `$QA_DIR/dest`.
4. Run `Paste`.
5. Expected: an operation banner appears, item count advances, the banner reaches completed state, and all files exist in `$QA_DIR/dest`.

## Cancel Progress

1. Increase the fixture size if the copy finishes too quickly.
2. Repeat the copy flow.
3. Press `Cancel` while the operation banner is visible.
4. Expected: the banner changes to canceled, or the operation stops before all queued top-level items complete. Already copied files remain.

Result on 2026-06-28:

- Used `$HOME/MyMacFinderLargeOperationQA/source-many` with 5,000 generated files.
- Selected all files in the app UI, copied them, opened `dest-cancel`, and pasted.
- The banner showed `Copying 5000 items` with advancing item progress and a Cancel button.
- Pressing Cancel changed the action button to Dismiss and stopped the operation at 385 copied files.

## ZIP Progress

1. Select copied fixture files in `$QA_DIR/dest`.
2. Run `Compress to ZIP`.
3. Expected: the banner shows a writing archive phase and reaches completed state.

Result on 2026-06-28:

- Selected the copied fixture folder in the app UI and ran `Compress to ZIP`.
- The banner showed compression progress and reached completed state.

## Cleanup

Run:

```bash
rm -rf "$QA_DIR"
```
