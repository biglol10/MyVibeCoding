# Permission Policy Manual QA

## Scope

- Folder access recovery from permission-denied errors.
- Settings > Privacy & Access controls.
- Security-scoped folder grant persistence.
- Personal non-sandbox build behavior.

## Automated Gate

Run before manual QA:

```bash
swift test
git diff --check
./scripts/build_app.sh
```

## Fixture

```bash
mkdir -p "$HOME/MyMacFinderPermissionQA/granted"
printf "permission qa\n" > "$HOME/MyMacFinderPermissionQA/granted/readme.txt"
```

## Manual Steps

1. Launch `build/MyMacFinder.app`.
2. Open Settings > Privacy & Access.
3. Verify Sandbox shows the current build policy. Personal builds should show an unrestricted status.
4. Click Choose Folder... and select `$HOME/MyMacFinderPermissionQA/granted`.
5. Verify the selected folder appears in the granted folder list.
6. Click the row remove button and verify the folder disappears.
7. Click Choose Folder... again and select the same folder.
8. Click Reset Folder Access and verify the list becomes empty.
9. Click Choose Folder... again and select the same folder.
10. Navigate the main file list to `$HOME/MyMacFinderPermissionQA/granted`.
11. Verify `readme.txt` is visible and the file list remains interactive.
12. Quit the app and launch it again.
13. Reopen Settings > Privacy & Access and verify the selected folder grant persists.

## Cleanup

```bash
rm -rf "$HOME/MyMacFinderPermissionQA"
```

## Pass Criteria

- Folder grants can be added, removed, reset, and persisted across app launches.
- Permission recovery buttons do not lose the denied path when the alert closes.
- No app crash, hang, or stale error alert appears during the flow.
