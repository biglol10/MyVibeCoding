# CaptureStudio Follow-up Hardening Plan

**Goal:** Fix confirmed editor, shortcut, recording-export, and personal-install defects without changing unrelated product behavior.

**Scope:** MyCaptureProgram only. Tests and diagnostics use isolated temporary paths; no TCC, Desktop, Documents, installed app, or user preferences are modified.

## Tasks

- [x] Add regression tests for horizontal and vertical arrow drags, then make arrow validation distance-based.
- [x] Add regression tests for unsafe global shortcut modifiers and persisted legacy values, then reject or repair unsafe bindings.
- [x] Add trim-input parsing tests, then report invalid nonblank values instead of silently coercing them.
- [x] Add GIF planning tests for non-finite or empty media duration, then fail safely before frame-count conversion.
- [x] Add a macOS Bash regression test for unprivileged install commands, then replace empty-array command prefixes in local and personal installers.
- [x] Re-audit dirty-document termination and temporary recording ownership after the focused fixes.
- [x] Run focused tests, the full test suite, Debug/Release builds, script syntax checks, and Git hygiene checks in isolated temporary paths.
- [x] Review the final diff for behavior regressions and document any live UI/TCC boundaries.
