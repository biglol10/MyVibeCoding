# File Operations Stabilization Manual QA

## Setup

Run:

```bash
fixture="$(scripts/create-file-operations-qa-fixture.sh)"
scripts/create-app-bundle.sh --configuration debug
open .build/app/MyMacFinder.app
```

Navigate the app to `$fixture/source`.

## Collision Handling

1. Copy `collide.txt`.
2. Navigate to `$fixture/dest`.
3. Paste.
4. In the conflict dialog choose `Keep Both`.
5. Expected: `$fixture/dest/collide.txt` still contains `destination collide`; `$fixture/dest/collide copy.txt` contains `source collide`.

Repeat the same copy flow and choose `Replace`.
Expected: `$fixture/dest/collide.txt` contains `source collide`.

Repeat the same copy flow and choose `Skip`.
Expected: destination files do not change.

Repeat the same copy flow and choose `Cancel`.
Expected: destination files do not change and no alert appears.

## Undo

1. Create a new folder.
2. Press `Cmd+Z`.
3. Expected: new folder disappears.

1. Rename `rename-me.txt` to `renamed.txt`.
2. Press `Cmd+Z`.
3. Expected: `rename-me.txt` is restored.

1. Duplicate `duplicate-me.txt`.
2. Press `Cmd+Z`.
3. Expected: duplicate disappears and original remains.

1. Cut `alpha.txt`, navigate to `$fixture/dest`, paste.
2. Press `Cmd+Z`.
3. Expected: `alpha.txt` returns to `$fixture/source`.

1. Move `duplicate-me.txt` to Trash.
2. Press `Cmd+Z`.
3. Expected: `duplicate-me.txt` is restored in `$fixture/source`.

## ZIP Extraction

1. Select `archive.zip`.
2. Run `Extract ZIP`.
3. Choose `Keep Both` when prompted for existing `archive` folder.
4. Expected: `archive copy/nested/readme.txt` exists and contains `zip readme`.
5. Press `Cmd+Z`.
6. Expected: `archive copy` disappears.

## Drag and Drop

1. Drag `folder-a` onto `$fixture/drag-target` in the app.
2. Expected: folder moves or copies according to the shown operation.
3. Press `Cmd+Z`.
4. Expected: operation is reverted.

## External Sync

Run:

```bash
printf "external\n" > "$fixture/source/external-created.txt"
mv "$fixture/source/external-created.txt" "$fixture/source/external-renamed.txt"
rm "$fixture/source/external-renamed.txt"
```

Expected: app updates without manual refresh after each operation.

## Large Folder Smoke

Navigate to `$fixture/large`.
Expected: table remains scrollable and selection works.

## Cleanup

Run:

```bash
rm -rf "$fixture"
```
