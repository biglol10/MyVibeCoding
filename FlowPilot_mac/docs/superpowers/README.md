# FlowPilot Superpowers Planning Archive

Files in `docs/superpowers/specs/` and `docs/superpowers/plans/` are historical planning artifacts from earlier
implementation passes. They are useful for understanding why a change was made, but they are not the current source of
truth for setup, packaging, or supported behavior.

Use these current documents instead:

- Project overview and common commands: [`../../README.md`](../../README.md)
- macOS development and packaging: [`../macos-development.md`](../macos-development.md)
- macOS distribution and notarization: [`../macos-distribution.md`](../macos-distribution.md)

Known examples of changed scope since the archived plans:

- macOS idle detection is now implemented.
- The SwiftUI native macOS app now reads the existing FlowPilot database and has native collection/packaging scripts.
- Safari domain tracking is available in the SwiftUI native app through macOS Automation when permission is granted.
- Personal install packages now include scripts that replace `/Applications/FlowPilot.app` and remove quarantine.
