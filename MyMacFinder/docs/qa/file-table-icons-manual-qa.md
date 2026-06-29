# File Table Icons Manual QA

## Scope

- Name column displays an icon before each file or folder name.
- macOS file icons are used for real filesystem entries.
- Archive-backed virtual entries receive fallback icons.
- Existing table columns, truncation, and row behavior remain intact.

## Automated Gate

Run before manual QA:

```bash
swift test
swift build
git diff --check
./scripts/build_app.sh
```

## Fixture

```bash
fixture="$HOME/MyMacFinderIconQA"
rm -rf "$fixture"
mkdir -p "$fixture/Folder"
printf 'console.log("hello")\n' > "$fixture/script.js"
printf 'export const value: number = 1\n' > "$fixture/component.ts"
printf 'notes\n' > "$fixture/notes.txt"
printf '%s\n' '%PDF-1.4' '1 0 obj <<>> endobj' 'trailer <<>>' '%%EOF' > "$fixture/paper.pdf"
printf '\x89PNG\r\n\x1a\n' > "$fixture/image.png"
(cd "$fixture" && zip -qr archive.zip Folder notes.txt)
```

## Manual Steps

1. Launch `build/MyMacFinder.app`.
2. Navigate to `$HOME/MyMacFinderIconQA`.
3. Confirm each visible Name cell has an icon before the text.
4. Confirm the fixture includes icons for `Folder`, `archive.zip`, `component.ts`, `image.png`, `notes.txt`, `paper.pdf`, and `script.js`.
5. Open `archive.zip`.
6. Confirm ZIP-backed `Folder` and `notes.txt` entries also show icons before their names.

## 2026-06-28 Result

- Automated: `swift test` passed 212 tests with 0 failures.
- Automated: `swift build` passed.
- Automated: `git diff --check` passed.
- Automated: `./scripts/build_app.sh` created `build/MyMacFinder.app`.
- Manual: app launched from `build/MyMacFinder.app`.
- Manual: home folder rows exposed `image` plus `text` in the Name column accessibility tree.
- Manual: `$HOME/MyMacFinderIconQA` showed icons before `Folder`, `archive.zip`, `component.ts`, `image.png`, `notes.txt`, `paper.pdf`, and `script.js`.
- Manual: the app screenshot showed folder, document, image, PDF, and script-like file icons before filenames.
- Manual: opening `archive.zip` showed fallback icons for ZIP-backed `Folder` and `notes.txt`.
