# MyMacClean Fancy Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the default MyMacClean app icon with the approved Dark Utility Mark icon and wire it into the built `.app`.

**Architecture:** Keep the app icon as a project-owned resource under `Sources/MyMacCleanApp/Resources`. The app bundle plist declares the icon by filename, and `scripts/build-app-bundle.sh` copies the `.icns` into `Contents/Resources` during packaging.

**Tech Stack:** Swift Package Manager, XCTest, macOS `sips`, `iconutil`, shell packaging script.

---

## File Structure

Create:

- `Tests/MyMacCleanAppSupportTests/AppBundleIconResourceTests.swift`: verifies the source plist and icon resource contract.
- `Sources/MyMacCleanApp/Resources/MyMacCleanIcon.icns`: macOS icon file built from generated iconset sizes.

Modify:

- `Sources/MyMacCleanApp/Resources/MyMacCleanInfo.plist`: add `CFBundleIconFile` set to `MyMacCleanIcon`.
- `scripts/build-app-bundle.sh`: copy `MyMacCleanIcon.icns` into the built app bundle resources.

---

### Task 1: Add Icon Resource Contract Test

**Files:**

- Create: `Tests/MyMacCleanAppSupportTests/AppBundleIconResourceTests.swift`

- [ ] **Step 1: Write failing test**

Create `Tests/MyMacCleanAppSupportTests/AppBundleIconResourceTests.swift`:

```swift
import XCTest

final class AppBundleIconResourceTests: XCTestCase {
    func testAppInfoPlistDeclaresBundledIconResource() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let plistURL = root.appendingPathComponent("Sources/MyMacCleanApp/Resources/MyMacCleanInfo.plist")
        let iconURL = root.appendingPathComponent("Sources/MyMacCleanApp/Resources/MyMacCleanIcon.icns")

        let plistData = try Data(contentsOf: plistURL)
        guard let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            XCTFail("MyMacCleanInfo.plist should be a dictionary")
            return
        }

        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "MyMacCleanIcon")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path), "MyMacCleanIcon.icns should exist in app resources")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter AppBundleIconResourceTests
```

Expected: FAIL because `CFBundleIconFile` is not set and `MyMacCleanIcon.icns` does not exist.

- [ ] **Step 3: Commit failing test**

Do not commit this failing test by itself. Continue to Task 2 and commit when green.

---

### Task 2: Generate Icon and Wire Bundle Metadata

**Files:**

- Create: `Sources/MyMacCleanApp/Resources/MyMacCleanIcon.icns`
- Modify: `Sources/MyMacCleanApp/Resources/MyMacCleanInfo.plist`
- Modify: `scripts/build-app-bundle.sh`

- [ ] **Step 1: Generate icon PNG and `.icns`**

Generate a 1024x1024 Dark Utility Mark source PNG with a dark graphite rounded-square background, a central white `M` utility mark, and a mint cleanup check. Convert it to `MyMacCleanIcon.icns` using a temporary `.iconset`.

- [ ] **Step 2: Add plist icon declaration**

Insert into `Sources/MyMacCleanApp/Resources/MyMacCleanInfo.plist`:

```xml
    <key>CFBundleIconFile</key>
    <string>MyMacCleanIcon</string>
```

- [ ] **Step 3: Copy icon during bundle build**

Add to `scripts/build-app-bundle.sh` after copying `Info.plist`:

```bash
cp "$ROOT_DIR/Sources/MyMacCleanApp/Resources/MyMacCleanIcon.icns" "$RESOURCES_DIR/MyMacCleanIcon.icns"
```

- [ ] **Step 4: Run focused test**

Run:

```bash
swift test --filter AppBundleIconResourceTests
```

Expected: PASS.

- [ ] **Step 5: Commit icon wiring**

Run:

```bash
git add Tests/MyMacCleanAppSupportTests/AppBundleIconResourceTests.swift \
  Sources/MyMacCleanApp/Resources/MyMacCleanInfo.plist \
  Sources/MyMacCleanApp/Resources/MyMacCleanIcon.icns \
  scripts/build-app-bundle.sh
git commit -m "feat: add custom app icon"
```

---

### Task 3: Verify Built App Bundle

**Files:**

- No source files should be modified unless verification reveals a bug.

- [ ] **Step 1: Build app bundle**

Run:

```bash
scripts/build-app-bundle.sh
```

Expected: exits 0 and prints `dist/MyMacClean.app`.

- [ ] **Step 2: Verify built plist and icon file**

Run:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' dist/MyMacClean.app/Contents/Info.plist
test -f dist/MyMacClean.app/Contents/Resources/MyMacCleanIcon.icns
```

Expected: plist prints `MyMacCleanIcon`; `test -f` exits 0.

- [ ] **Step 3: Run full test suite**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 4: Verify git status**

Run:

```bash
git status --short
```

Expected: no uncommitted source changes.
