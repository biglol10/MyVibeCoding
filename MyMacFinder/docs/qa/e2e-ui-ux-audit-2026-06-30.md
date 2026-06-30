# E2E UI/UX Audit - 2026-06-30

## Scope

- Built and launched `build/MyMacFinder.app` directly.
- Used `/Users/biglol/MyMacFinderE2EQA` as the manual QA fixture.
- Covered home navigation, sidebar recent navigation, path/search focus transitions, Return key open behavior, inspector selection updates, large folder scrolling, and column readability.

## Findings Fixed

- Selecting a folder and pressing Return could fail to open it when the event arrived through `insertNewline:` or when focus stayed on the window after toolbar/search use.
- Clicking a search result did not always clear toolbar text-input focus, so Return could be swallowed by stale focus routing.
- Path input values set through accessibility automation could end editing without submitting the edited path.
- A stale accessibility-provided path value could override a later manual text change.
- The file table gave extra width to the last column, leaving `Name` and `Kind` unnecessarily truncated.
- Horizontal/vertical scroll position could carry across folder changes, so a new folder could open partially scrolled.

## Manual Checks

- Home list renders and inspector shows "No Selection" initially.
- Selecting `MyMacFinderE2EQA` updates inspector and exposes Open, Quick Look, Reveal, Copy Path, Edit Tags, and Calculate Size actions.
- Pressing Return on selected `MyMacFinderE2EQA` navigates into the folder and updates the path input.
- Searching for `source`, selecting the result, and pressing Return opens the folder and clears the search field.
- Sidebar Recent Folders navigation updates the path input and does not leave toolbar focus stuck.
- `large` folder opens, virtualized table shows only visible rows, and scrolling jumps through the file list without rendering all rows at once.
- Column defaults now keep `Name` wider and give `Kind` enough width before `Tags`.

## Automated Verification

```bash
swift test --enable-code-coverage
```

Result: 324 tests / 0 failures.

Focused tests added or updated:

- `PathInputFieldTests`
- `FileTableViewReuseTests`
- `ExplorerShortcutRoutingTests`

## Notes

- A previously installed `/Applications/MyMacFinder.app` can confuse manual QA if it is already running. For QA, launch the built app by full path: `open -n /Users/biglol/Desktop/practice/MyMacFinder/build/MyMacFinder.app`.
