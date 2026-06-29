# Path Command and Open With Manual QA

Date: 2026-06-29

Build:

```bash
./scripts/build_app.sh
open build/MyMacFinder.app
```

## Checks

- Relaunched `build/MyMacFinder.app` after killing the previous running instance so the newest binary was active.
- Focused the path input at `/Users/biglol`, entered `cmd`, and pressed Return.
- Confirmed the app did not show `Path does not exist: /Users/biglol/cmd`.
- Confirmed the path input returned to `/Users/biglol` after command execution.
- Confirmed Terminal was running after the command.
- Confirmed MyMacFinder remained running after Terminal launch.
- Confirmed the rebuilt app process stayed alive after an automated `Cmd+L`, `cmd`, Return manual pass.
- Confirmed no new MyMacFinder crash report appeared in `~/Library/Logs/DiagnosticReports`.
- Clicked the path input, pressed `Cmd+A`, and confirmed the selected text stayed inside the path field instead of routing to table Select All.
- Entered `cmd` after `Cmd+A` and confirmed Terminal opened while MyMacFinder kept running.
- Right-clicked the `Desktop` folder row.
- Confirmed the context menu includes:
  - `Open With`
  - `Open in Terminal`
  - `Open in VS Code`
- Right-clicked the `dump.rdb` file row.
- Confirmed `Open With` shows compatible applications, including `Code`, plus `Choose Application...`.

## Notes

- The first manual attempt hit the old running app process and reproduced the previous path error. After quitting and relaunching the rebuilt app, the new behavior worked.
- A later manual pass found a stale focus edge case where `Cmd+A` could be stolen by global shortcut routing. Regression coverage now makes shortcut routing yield to the actual focused AppKit text editor even if the stored toolbar focus flag is stale.
- The file `Open With` menu was inspected without launching a selected third-party app from the menu.
- Regression coverage added for duplicate `NSWorkspace.open` completion callbacks so `code .` through VS Code app and file `Open With` launches do not terminate MyMacFinder if AppKit reports more than one completion.
- `cmd` / `terminal` launch Terminal as fire-and-forget requests. MyMacFinder checks that Terminal.app exists, then does not await Terminal's completion callback because Terminal can report a completion error even after opening successfully.
