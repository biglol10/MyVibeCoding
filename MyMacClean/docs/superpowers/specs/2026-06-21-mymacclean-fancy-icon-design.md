# MyMacClean Fancy App Icon Design

## Goal

Replace the default macOS application icon with a polished icon that makes MyMacClean feel like a premium Mac utility.

## Approved Direction

The selected direction is **C: Dark Utility Mark**.

The icon should use:

- A macOS-style rounded square silhouette.
- A dark graphite or metal-like premium background.
- A central `M`-inspired utility mark.
- A small mint cleanup/check signal in the lower-right area.
- High contrast so it remains recognizable at Dock size.

## Implementation

Add a project-owned app icon resource:

- `Sources/MyMacCleanApp/Resources/MyMacCleanIcon.icns`

Wire the icon into the app bundle:

- Add `CFBundleIconFile` to `Sources/MyMacCleanApp/Resources/MyMacCleanInfo.plist`.
- Update `scripts/build-app-bundle.sh` to copy the icon into `Contents/Resources`.

The build output must include:

- `dist/MyMacClean.app/Contents/Resources/MyMacCleanIcon.icns`
- `CFBundleIconFile` set to `MyMacCleanIcon`

## Out Of Scope

- Developer ID signing.
- Notarization.
- Alternate icon switching inside the app.
- Redesigning in-app UI.

## Verification

Run:

```bash
scripts/build-app-bundle.sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' dist/MyMacClean.app/Contents/Info.plist
test -f dist/MyMacClean.app/Contents/Resources/MyMacCleanIcon.icns
swift test
```

Expected:

- The build script exits 0.
- The plist prints `MyMacCleanIcon`.
- The icon file exists in the built app bundle.
- The Swift test suite passes.
