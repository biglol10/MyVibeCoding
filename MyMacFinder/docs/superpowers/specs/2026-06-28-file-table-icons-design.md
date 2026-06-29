# File Table Icons Design

## Goal

Show a compact icon before each file or folder name in the main table so users can identify folders, images, JavaScript/TypeScript files, PDFs, ZIP files, videos, and other common file types without checking the Kind column.

## User Experience

- The Name column displays a 16x16 icon followed by the existing filename text.
- Folder rows use the macOS folder icon.
- Real filesystem files use the macOS document/type icon resolved by `NSWorkspace.shared.icon(forFile:)`, so images, PDFs, JS, TS, ZIP, video, and unknown file types follow the system's icon set.
- ZIP-backed virtual rows use fallback icons because their `FileEntry.url` is not a real filesystem path.
- Long names keep the current middle truncation behavior.
- Selection, row height, sorting, context menus, drag and drop, and keyboard shortcuts continue to behave as they do now.

## Architecture

The change stays inside the existing AppKit table bridge. `FileTableView.Coordinator` creates a name cell with an `NSImageView` and `NSTextField`, while all non-name columns keep text-only cells. A small `icon(for:)` helper resolves real filesystem icons through `NSWorkspace`, then falls back to system symbols for archive-backed or synthetic entries.

The fallback mapping is intentionally conservative:

- folder, volume, ZIP virtual folder: folder-style icons
- package: app/package icon
- symlink: alias icon
- ZIP virtual file and unknown file: document icon
- common extensions can use system file icons when the URL exists, so no custom asset catalog is needed

## Testing

Automated tests cover the table bridge directly:

- Name cells include a non-empty `NSImageView`.
- Text-only columns do not gain icons.
- Archive-backed virtual entries still get a fallback icon.
- Existing text truncation constraints remain intact.

Manual E2E uses a fixture folder with a folder, `image.png`, `script.js`, `component.ts`, `paper.pdf`, `archive.zip`, and a generic text file. The app is launched from the built bundle, navigated to the fixture, and the accessibility tree/screenshot are inspected to confirm icons render in front of names.

## Spec Review

- No placeholder requirements remain.
- Scope is limited to table row icons, not custom icon artwork or icon themes.
- The implementation does not alter file operation behavior.
- The E2E requirement is explicit and uses a generated fixture folder only.
