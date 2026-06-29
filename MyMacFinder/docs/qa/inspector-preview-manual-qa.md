# Inspector Preview Manual QA

Date: 2026-06-29

Build under test:

```bash
./scripts/build_app.sh
open build/MyMacFinder.app
```

Fixture:

```text
/Users/biglol/MyMacFinderPreviewQA
  binary.txt
  large.log
  preview.md
```

Checks performed:

- Opened `build/MyMacFinder.app`.
- Navigated to `/Users/biglol/MyMacFinderPreviewQA` from Recent Folders.
- Verified rapid selection changes continue to update table selection immediately while preview loads after a short debounce.
- Selected `preview.md`.
  - Expected: Inspector shows inline text preview.
  - Observed: Inspector showed `Text Preview`, `UTF-8`, and the Markdown content.
- Selected `large.log`.
  - Expected: Inspector shows inline text preview with truncation status.
  - Observed: Inspector showed `Text Preview`, `UTF-8`, `Truncated`, and the beginning of the log content.
- Selected `binary.txt`, a `.txt` file containing a NUL byte.
  - Expected: Inspector does not render binary bytes as text.
  - Observed: Inspector showed visual fallback and `Binary file preview is not available.`

Result: pass.
