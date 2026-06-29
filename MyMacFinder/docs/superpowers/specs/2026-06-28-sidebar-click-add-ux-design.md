# Sidebar Click And Add UX Design

## Context

The sidebar already supports persisted Favorites, Recent Folders, and Locations. Users can add a selected folder from the file table context menu or add the active folder through the small plus button in the Favorites header, but the add path is not obvious. Sidebar navigation rows also use plain SwiftUI buttons whose label content defines the hit area, so the blank space to the right of "Home" and other labels does not reliably activate the row.

## Design

Make every navigable sidebar row behave like a full-width row. Favorites, Recent Folders, and Locations rows should use the same label treatment: icon and title on the left, a row-width content shape, and left alignment across the available sidebar width. Missing favorites remain visually secondary and disabled for navigation.

Expose favorite registration as an explicit row inside Favorites: "Add Current Folder". It uses the existing `ExplorerStore.addActiveFolderToFavorites()` behavior and is disabled when the active filesystem folder is already in Favorites or when the active location cannot be favorited. The existing header plus button remains for fast access, but it uses the same enablement rule so duplicates are not presented as a meaningful action.

## Scope

- In scope: row-wide sidebar hit targets, clearer add-current-folder affordance, duplicate-aware add enablement, focused tests, and manual QA.
- Out of scope: editable custom sidebar sections such as a user-managed Developer group. That is a separate model/UI feature because the current app only persists Favorites and Recent Folders.

## Testing

Add a focused store test for duplicate-aware active-folder favorite enablement. Use manual QA to confirm the row-wide click behavior because SwiftUI hit testing is visual/input behavior rather than store behavior.
