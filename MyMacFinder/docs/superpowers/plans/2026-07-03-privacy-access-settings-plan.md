# Privacy Access Settings Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the sparse Privacy & Access settings `Form` with a polished, top-aligned SwiftUI settings panel while keeping current permission behavior unchanged.

**Architecture:** Add a focused `PrivacyAccessSettingsView` that receives store state and action closures from `MyMacFinderApp`. The settings scene remains the owner of app state and only delegates the Privacy tab layout to the new view. Tests verify the new view is constructible in empty and non-empty grant states.

**Tech Stack:** Swift, SwiftUI, XCTest, Swift Package Manager, existing MyMacFinder app scripts.

---

## File Structure

- Create `Sources/MyMacFinder/App/PrivacyAccessSettingsView.swift`: dedicated SwiftUI view for the Privacy & Access settings tab.
- Modify `Sources/MyMacFinder/App/MyMacFinderApp.swift`: replace the second `Form` tab with `PrivacyAccessSettingsView`.
- Create `Tests/MyMacFinderTests/PrivacyAccessSettingsViewTests.swift`: wiring tests for empty and non-empty states.
- Modify `README.md`: update the recent test count after the new tests land.

## Task 1: Add View Wiring Tests

**Files:**
- Create: `Tests/MyMacFinderTests/PrivacyAccessSettingsViewTests.swift`
- Later create: `Sources/MyMacFinder/App/PrivacyAccessSettingsView.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import SwiftUI
import XCTest
@testable import MyMacFinder

@MainActor
final class PrivacyAccessSettingsViewTests: XCTestCase {
    func testPrivacyAccessSettingsViewBuildsForEmptyFolderGrants() {
        let view = PrivacyAccessSettingsView(
            sandboxPolicy: SandboxPolicySummary(isSandboxed: false),
            grantedFolderSummaries: [],
            onChooseFolder: {},
            onOpenPrivacySettings: {},
            onRemoveGrant: { _ in },
            onResetGrants: {}
        )

        XCTAssertNotNil(view.body)
    }

    func testPrivacyAccessSettingsViewBuildsForGrantedFolders() {
        let view = PrivacyAccessSettingsView(
            sandboxPolicy: SandboxPolicySummary(isSandboxed: true),
            grantedFolderSummaries: [
                FolderAccessGrantSummary(
                    grant: FolderAccessGrant(
                        url: URL(fileURLWithPath: "/Users/biglol/Documents/Work", isDirectory: true),
                        bookmarkData: Data()
                    )
                )
            ],
            onChooseFolder: {},
            onOpenPrivacySettings: {},
            onRemoveGrant: { _ in },
            onResetGrants: {}
        )

        XCTAssertNotNil(view.body)
    }
}
```

- [ ] **Step 2: Run the tests to verify RED**

Run: `swift test --filter PrivacyAccessSettingsViewTests`

Expected: build fails because `PrivacyAccessSettingsView` is not defined.

## Task 2: Implement PrivacyAccessSettingsView

**Files:**
- Create: `Sources/MyMacFinder/App/PrivacyAccessSettingsView.swift`

- [ ] **Step 1: Add the new SwiftUI view**

Implement:

```swift
import SwiftUI

struct PrivacyAccessSettingsView: View {
    let sandboxPolicy: SandboxPolicySummary
    let grantedFolderSummaries: [FolderAccessGrantSummary]
    let onChooseFolder: () -> Void
    let onOpenPrivacySettings: () -> Void
    let onRemoveGrant: (FolderAccessGrantSummary.ID) -> Void
    let onResetGrants: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusPanel
                actionsPanel
                foldersPanel
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(maxWidth: 620, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
```

Add private subviews for the header, status panel, actions panel, folders panel, empty state, and folder rows. Use system colors such as `.quaternary.opacity(0.35)`, `.secondary`, `.accentColor`, and `.separator`.

- [ ] **Step 2: Run the view tests to verify GREEN**

Run: `swift test --filter PrivacyAccessSettingsViewTests`

Expected: 2 tests pass.

## Task 3: Wire the View Into Settings

**Files:**
- Modify: `Sources/MyMacFinder/App/MyMacFinderApp.swift`

- [ ] **Step 1: Replace only the Privacy tab body**

Replace the second `Form { Section("Privacy & Access") { ... } }` with:

```swift
PrivacyAccessSettingsView(
    sandboxPolicy: explorerStore.sandboxPolicy,
    grantedFolderSummaries: explorerStore.grantedFolderSummaries,
    onChooseFolder: {
        Task {
            await explorerStore.chooseFolderForAccess()
        }
    },
    onOpenPrivacySettings: openPrivacySettings,
    onRemoveGrant: { id in
        Task {
            await explorerStore.removeGrantedFolder(id: id)
        }
    },
    onResetGrants: {
        Task {
            await explorerStore.resetGrantedFolders()
        }
    }
)
```

Keep the existing `.tabItem { Label("Privacy & Access", systemImage: "lock.shield") }`.

- [ ] **Step 2: Run focused settings/view tests**

Run: `swift test --filter PrivacyAccessSettingsViewTests`

Expected: pass.

## Task 4: Verify and Package

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Run full verification**

Run:

```sh
swift test --enable-code-coverage
swift build
git diff --check
./scripts/build_app.sh
./scripts/verify-app-icon.sh
codesign --verify --deep --strict --verbose=2 build/MyMacFinder.app
./scripts/package_personal.sh
unzip -t dist/MyMacFinder-personal-mac.zip
```

Expected: all commands exit 0. `swift test --enable-code-coverage` reports 366 tests with 0 failures after the two new tests are added.

- [ ] **Step 2: Update README**

At the time of this plan, change the recent verification line from `364 tests / 0 failures` to `366 tests / 0 failures`.

- [ ] **Step 3: Commit implementation**

```sh
git add README.md Sources/MyMacFinder/App/MyMacFinderApp.swift Sources/MyMacFinder/App/PrivacyAccessSettingsView.swift Tests/MyMacFinderTests/PrivacyAccessSettingsViewTests.swift
git commit -m "style: refresh privacy access settings"
```
