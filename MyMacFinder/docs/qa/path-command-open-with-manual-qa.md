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
- Right-clicked the `Desktop` folder row.
- Confirmed the context menu includes:
  - `Open With`
  - `Open in Terminal`
  - `Open in VS Code`
- Right-clicked the `dump.rdb` file row.
- Confirmed `Open With` shows compatible applications, including `Code`, plus `Choose Application...`.

## Notes

- The first manual attempt hit the old running app process and reproduced the previous path error. After quitting and relaunching the rebuilt app, the new behavior worked.
- The file `Open With` menu was inspected without launching a selected third-party app from the menu.
