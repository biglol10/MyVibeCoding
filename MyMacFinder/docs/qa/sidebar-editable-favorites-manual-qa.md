# Sidebar Editable Favorites Manual QA

## Scope

- Persisted editable Favorites.
- Recent Folders updates.
- Locations remains separate from user-owned favorites.
- Missing favorite path handling.
- Favorite reorder controls.

## Automated Gate

Run before manual QA:

```bash
swift test
git diff --check
./scripts/build_app.sh
```

## Fixture

```bash
fixture="$HOME/MyMacFinderSidebarQA"
rm -rf "$fixture"
mkdir -p "$fixture/Parent/Child" "$fixture/MissingThenRemove"
printf "alpha\n" > "$fixture/Parent/alpha.txt"
```

## Manual Steps

1. Back up current app defaults and clear only `MyMacFinder.SidebarState`.
2. Launch `build/MyMacFinder.app`.
3. Navigate to `$HOME/MyMacFinderSidebarQA`.
4. Confirm the sidebar has separate Favorites, Recent Folders, and Locations sections.
5. Navigate into `Parent`. Expected: Recent Folders updates with `Parent` first.
6. Select `Child`, right-click, choose Add to Favorites. Expected: `Child` appears in Favorites.
7. Use the Favorites header plus button while in `Parent`. Expected: `Parent` appears in Favorites.
8. Right-click `Parent` in Favorites and choose Remove from Favorites. Expected: `Parent` is removed.
9. Navigate into `MissingThenRemove` and use the Favorites header plus button. Expected: `MissingThenRemove` appears in Favorites.
10. Quit the app, delete `$HOME/MyMacFinderSidebarQA/MissingThenRemove` externally, and relaunch.
11. Confirm `MissingThenRemove` remains in Favorites with a disabled/secondary visual state and clicking it does not navigate or crash.
12. Right-click `Child` in Favorites. Expected: Move Up, Move Down, and Remove from Favorites are available.
13. Choose Move Down. Expected: `Child` moves below `MissingThenRemove`.
14. Confirm Locations still lists mounted volumes separately.
15. Quit the app, remove the fixture, and restore the backed-up defaults.

## 2026-06-28 Result

- Automated: `swift test` passed 194 tests after adding Move Up and Move Down.
- Automated: focused sidebar tests passed 16 tests.
- Automated: `git diff --check` passed before manual QA.
- Automated: `./scripts/build_app.sh` produced `build/MyMacFinder.app`.
- Manual: default Favorites seeded as Home, Desktop, Documents, Downloads, and Applications.
- Manual: Recent Folders updated when navigating into `MyMacFinderSidebarQA`, `Parent`, and `MissingThenRemove`.
- Manual: file row context menu exposed Add to Favorites and added selected folder `Child`.
- Manual: Favorites header plus added the current folder.
- Manual: favorite context menu removed `Parent`.
- Manual: missing favorite survived relaunch, rendered in a secondary disabled-looking state, and clicking it did not navigate or crash.
- Manual: favorite context menu exposed Move Up, Move Down, and Remove from Favorites.
- Manual: Move Down reordered `Child` below `MissingThenRemove`.
- Manual: Locations stayed separate and showed `Macintosh HD`.
- Cleanup: QA fixture was removed and app defaults were restored from the pre-QA backup.
