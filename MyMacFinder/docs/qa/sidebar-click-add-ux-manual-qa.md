# Sidebar Click And Add UX Manual QA

## Scope

- Sidebar rows use full-width click targets.
- Favorites exposes a visible Add Current Folder row.
- Active folder add controls disable when the folder is already in Favorites.
- App defaults are restored after QA.

## Automated Gate

```bash
swift test
git diff --check
./scripts/build_app.sh
```

## Manual Result - 2026-06-28

- Backed up `com.biglol.MyMacFinder` defaults before manual QA.
- Launched `build/MyMacFinder.app`.
- Confirmed Favorites shows a visible `Add Current Folder` row.
- Navigated to `/Users`, clicked the Favorites header plus button, and confirmed `Users` appeared in Favorites.
- Confirmed the header plus button and `Add Current Folder` row disable after the active folder is already favorited.
- Clicked the right edge of the `Applications` favorite row, away from the label text, and confirmed the app navigated to `/Applications`.
- Restored the pre-QA defaults and removed the temporary QA fixture.

## Notes

- `Desktop` can be affected by macOS privacy permissions, so row hit-target verification used `/Applications`.
- This change keeps Favorites context menu reorder actions. Drag reorder from the previous SwiftUI `List` sidebar is not present in the custom full-width sidebar.
