# shadcn UI Migration Design

## Goal

Replace FlowPilot's custom dashboard UI styling with a shadcn-style React UI layer while preserving existing collection, reporting, rules, review, refresh, and persistence behavior.

## Scope

The migration covers the React app under `src/`. It does not change Rust collectors, storage, browser bridge APIs, classification behavior, or Tauri packaging logic.

## Recommended Approach

Use a local shadcn-compatible component layer in `src/components/ui` backed by Tailwind CSS tokens. This keeps the app independent from a runtime UI framework, follows shadcn's copy-in component model, and lets existing tests keep asserting behavior instead of implementation details.

Rejected alternatives:

- Full redesign plus page restructuring: higher visual churn and more regression risk.
- Keep current CSS and only rename classes: not a real shadcn migration and does not create reusable primitives.

## UI Architecture

- Add Tailwind and a shadcn-compatible theme in `src/index.css`.
- Add `components.json` so future shadcn components can be generated consistently.
- Add reusable primitives: `Button`, `Card`, `Badge`, `Input`, `Select`, `Table`, `Alert`, `Progress`, and `Separator`.
- Refactor feature components to compose these primitives.
- Keep chart and timeline data logic intact. Only the surrounding surfaces, labels, empty states, and controls move to the new primitives.

## UX Direction

FlowPilot remains a dense productivity dashboard, not a landing page. The visual direction is restrained: light neutral surfaces, clear borders, compact spacing, left navigation, readable tables, and Korean labels unchanged. Cards stay at 8px radius or less.

## Compatibility

Existing Windows and macOS behavior must remain unchanged because the migration only touches frontend rendering and package dependencies. Tauri commands and DTO shapes are unchanged.

## Testing

Add focused tests for the new UI primitives where behavior matters, then run the existing Vitest suite to prove page behavior still renders and interactions still work. Run the production build and a browser smoke check to catch Tailwind or layout integration problems.
