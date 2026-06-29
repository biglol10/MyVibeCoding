# Shortcut And Menu Parity Manual QA

## Scope

- File-table shortcut handling.
- Explorer menu command availability.
- Text-field editing safety for shortcuts that conflict with native editing.

## Automated Gate

Run before manual QA:

```bash
swift test
git diff --check
./scripts/build_app.sh
```

## Fixture

```bash
fixture="$HOME/MyMacFinderShortcutQA"
rm -rf "$fixture"
mkdir -p "$fixture/Parent/Child"
printf "alpha\n" > "$fixture/Parent/alpha.txt"
printf "beta\n" > "$fixture/Parent/beta.txt"
printf "child\n" > "$fixture/Parent/Child/readme.txt"
```

## Manual Steps

1. Launch `build/MyMacFinder.app`.
2. Navigate to `$HOME/MyMacFinderShortcutQA/Parent`.
3. Select `Child` and press Return. Expected: the pane opens `Child`.
4. Press Command-Up. Expected: the pane returns to `Parent`.
5. Select `Child` and press Command-Down. Expected: the pane opens `Child`.
6. Press Command-Left. Expected: the pane goes back to `Parent`.
7. Press Command-Right. Expected: the pane goes forward to `Child`.
8. Press Command-Up to return to `Parent`.
9. Press Command-A while the file table is focused. Expected: all visible rows are selected.
10. Select `alpha.txt` and press F2. Expected: the rename dialog opens. Cancel it.
11. Select `alpha.txt` and press Command-O. Expected: the file opens through the system default app or the command is accepted without changing folder state.
12. Press Command-I. Expected: the inspector toggles.
13. Open the Explorer menu. Expected: Back/Forward are enabled only when history exists, Open shows Command-O, Toggle Inspector shows Command-I, and Select All is present.
14. Focus the path field with Command-L.
15. Press Command-A in the path field. Expected: path text is selected, not table rows.
16. Press Command-Left and Command-Right in the path field. Expected: cursor movement stays in the text field and does not navigate pane history.
17. Focus the search field with Command-F.
18. Press Command-A in the search field. Expected: search text is selected, not table rows.

## Cleanup

```bash
rm -rf "$HOME/MyMacFinderShortcutQA"
```

## Pass Criteria

- Table-focused shortcuts perform file-manager actions.
- Text-field-focused shortcuts preserve native editing behavior.
- Explorer menu labels and disabled states match active command availability.

## 2026-06-28 Result

- Automated: `swift test` passed 184 tests.
- Automated: `git diff --check` passed.
- Automated: `./scripts/build_app.sh` produced `build/MyMacFinder.app`.
- Manual: Return opened the selected folder instead of rename.
- Manual: Command-Up, Command-Down, Command-Left, and Command-Right navigated as expected while the table was focused.
- Manual: Command-A selected all visible table rows while the table was focused.
- Manual: F2 opened the rename dialog for a single selected file and cancel left the file unchanged.
- Manual: Command-O was accepted on a selected file without changing folder state.
- Manual: Command-I hid and restored the inspector.
- Manual: Explorer menu exposed Select All, Open, Back, Forward, Go Up, and Toggle Inspector with Back/Forward availability matching navigation history.
- Manual: Command-A and Command-Left/Right in the path field stayed in text editing and did not navigate history.
- Manual: Command-A in the search field selected the search text and did not select table rows.
