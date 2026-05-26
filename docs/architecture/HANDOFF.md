# Handoff: Phase 2 Design System Extraction

## Focus

Pick up architecture cleanup at Phase 2: move reusable visual primitives into design-system/shared-component folders without changing product behavior or visuals.

Reference docs:

- `CONTEXT.md` for product terms.
- `docs/architecture/ARCHITECTURE.md` for target shape.
- `docs/architecture/PLAN.md` for phased migration.

## Current State

Phase 1 is complete.

Created:

- `NEARPrivateChat/App/AppEnvironment.swift`
- `NEARPrivateChat/App/AppLifecycle.swift`
- `NEARPrivateChat/App/RootView.swift`
- `NEARPrivateChat/App/StatusBanner.swift`
- `NEARPrivateChat/Core/Routing/AppRoute.swift`
- `NEARPrivateChat/Core/Routing/AppSheet.swift`
- `NEARPrivateChat/Core/Routing/AppRouter.swift`
- `NEARPrivateChat/Features/Setup/UserSetupView.swift`
- `NEARPrivateChat/Features/Setup/LegalTermsRequiredView.swift`

`NEARPrivateChatApp.swift` is now mostly app construction and dependency installation. `AppRouter` is injected as an `EnvironmentObject`, but feature-specific navigation and sheets still remain local until their feature extraction phases.

Codebase still has large concentration:

- `NEARPrivateChat/AppShellView.swift` owns home composition and still coordinates many UI surfaces through extracted sibling files.
- `NEARPrivateChat/ChatStore.swift` owns broad app state, streaming, routing decisions, persistence, sharing, files, projects, agent, settings.
- `NEARPrivateChat/Models.swift` mixes domain models, DTOs, storage helpers, design constants, and small UI components.

## Phase 2 Goal

Create:

- `NEARPrivateChat/Core/DesignSystem`
- `NEARPrivateChat/Shared/Components`
- `NEARPrivateChat/Shared/Components/Markdown`
- focused files for colors/tokens, typography helpers, haptics, chips, cards, rows, empty states, loading rows, toolbar/icon helpers, and markdown rendering

Move reusable visual primitives out of root/feature files. Keep visuals unchanged.

## Constraints

- Preserve behavior.
- Preserve visuals except for tiny layout glue required by moved code.
- No DB migrations.
- No localhost app.
- Use `pnpm` only for JS verifier work.
- Keep SwiftUI components small when extracting, but do not split purely for line count.
- Prefer feature-first/fractal folders.
- One component per file after extraction.
- For tiny docs/style-only work, skip build.

## Suggested Skills

- `build-ios-apps:swiftui-view-refactor` for moving SwiftUI components without behavior drift.
- `build-ios-apps:swiftui-ui-patterns` for keeping components idiomatic and reusable.
- `grill-with-docs` if a product term or hard architecture decision needs clarification.

## First Files To Inspect

- `NEARPrivateChat/AppShellView.swift`
- `NEARPrivateChat/AppHaptics.swift`
- `NEARPrivateChat/ChipFlowLayout.swift`
- `NEARPrivateChat/MarkdownRenderingViews.swift`
- `NEARPrivateChat/HomeSupportingViews.swift`
- `NEARPrivateChat/ChatMessageViews.swift`
- `NEARPrivateChat/ChatStore.swift`
- `NEARPrivateChat/Models.swift`
- `NEARPrivateChat.xcodeproj/project.pbxproj`

## Implementation Notes

- Move files by ownership, not just line count.
- Keep reusable primitives in `Core/DesignSystem` only when they are genuinely cross-feature.
- Keep feature-specific presentation in its feature until that feature extraction happens.
- Remove `private` from moved declarations only where another file must reference them.
- Project uses manual Xcode groups, not filesystem-synced groups. Add each new Swift file to `.pbxproj` target membership.
- Prefer moving complete small files first (`AppHaptics.swift`, `ChipFlowLayout.swift`, `MarkdownRenderingViews.swift`) before slicing `AppShellView.swift` again.

## Exit Checks

- Reusable visual primitives no longer default to `AppShellView.swift`.
- Markdown renderer lives under `Shared/Components/Markdown`.
- Haptics and layout helpers live under `Core/DesignSystem` or `Shared/Components`.
- Existing screens render the same.
- Build succeeds after Swift file/project changes.

## Known Open Decision

Next feature extraction after Phase 2 remains undecided:

- Recommended correctness path: Sharing first.
- Recommended fast file-size path: Home first.
