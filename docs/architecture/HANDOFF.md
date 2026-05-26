# Handoff: Phase 1 App Shell And Routing

## Focus

Pick up architecture cleanup at Phase 1: create app shell and routing foundation without changing product behavior.

Reference docs:

- `CONTEXT.md` for product terms.
- `docs/architecture/ARCHITECTURE.md` for target shape.
- `docs/architecture/PLAN.md` for phased migration.

## Current State

Docs only so far. No Swift refactor done in this pass.

Codebase still has large concentration:

- `NEARPrivateChat/AppShellView.swift` owns most UI surfaces.
- `NEARPrivateChat/ChatStore.swift` owns broad app state, streaming, routing decisions, persistence, sharing, files, projects, agent, settings.
- `NEARPrivateChat/Models.swift` mixes domain models, DTOs, storage helpers, design constants, and small UI components.
- `NEARPrivateChat/NEARPrivateChatApp.swift` creates `PrivateChatAPI`, `SessionStore`, `ChatStore`, then wires root auth/setup/legal/banner behavior inline.

## Phase 1 Goal

Create foundation only:

- `NEARPrivateChat/App/RootView.swift`
- `NEARPrivateChat/App/AppEnvironment.swift`
- `NEARPrivateChat/App/AppLifecycle.swift`
- `NEARPrivateChat/App/StatusBanner.swift`
- `NEARPrivateChat/Features/Setup/UserSetupView.swift`
- `NEARPrivateChat/Features/Setup/LegalTermsRequiredView.swift`
- `NEARPrivateChat/Core/Routing/AppRoute.swift`
- `NEARPrivateChat/Core/Routing/AppSheet.swift`
- `NEARPrivateChat/Core/Routing/AppRouter.swift`
- corresponding `NEARPrivateChat.xcodeproj/project.pbxproj` file refs/build-phase entries

Move root-level routing/lifecycle out of `NEARPrivateChatApp.swift`.

Keep `ChatStore` as compatibility facade. Do not split `ChatStore` yet.
Keep `SessionStore` name. Do not rename auth state in Phase 1.

## Constraints

- Preserve behavior.
- No DB migrations.
- No localhost app.
- Use `pnpm` only for JS verifier work.
- Do not use `codex/` branch prefix.
- Keep SwiftUI components small when extracting, but do not split purely for line count.
- Prefer feature-first/fractal folders.
- One component per file after extraction.
- For tiny docs/style-only work, skip build.

## Suggested Skills

- `build-ios-apps:swiftui-ui-patterns` for app wiring, `NavigationStack`, enum routes, sheet presentation.
- `build-ios-apps:swiftui-view-refactor` for moving root view logic without behavior drift.
- `grill-with-docs` if a product term or hard architecture decision needs clarification.

## First Files To Inspect

- `NEARPrivateChat/NEARPrivateChatApp.swift`
- `NEARPrivateChat/AppShellView.swift`
- `NEARPrivateChat/ChatStore.swift`
- `NEARPrivateChat/Models.swift`
- `NEARPrivateChat.xcodeproj/project.pbxproj`

## Implementation Notes

- Start by introducing route/sheet types without replacing every sheet in app.
- Extract `RootView` from `NEARPrivateChatApp.swift` first.
- Keep current `EnvironmentObject` injection during Phase 1 to reduce blast radius.
- Add `AppRouter` as `ObservableObject` owned by `@StateObject` and injected as `@EnvironmentObject`; avoid `@Observable` until later state cleanup.
- Move setup/legal/banner declarations out of `NEARPrivateChatApp.swift` too, not only `RootView`.
- Remove `private` from moved declarations only where another file needs to reference them.
- Project uses manual Xcode groups, not filesystem-synced groups. Add each new Swift file to `.pbxproj` target membership.
- Reset route path on sign-out/account switch.
- Preserve existing `.onOpenURL` behavior: session callback first, app deep link second.
- Keep setup/legal/banner presentation behavior same.

## Exit Checks

- `NEARPrivateChatApp.swift` is mostly app construction and dependency install.
- Root auth/setup/legal/banner behavior lives in `App/RootView.swift` or lifecycle helper.
- Setup/legal/banner views live in their own files, not a new root monolith.
- Route and sheet enum files exist.
- Existing sign-in, sign-out, deep link, setup rerun, delete confirmation, hosted handoff presentation still have clear owner.
- No Home, Chat, Sharing, Account, Security, Agent, Project, File, or Model Catalog extraction beyond root setup/legal support needed for this phase.
- Build succeeds after Swift/project changes.

## Known Open Decision

Next feature extraction after Phase 1 is undecided:

- Recommended correctness path: Sharing first.
- Recommended fast file-size path: Home first.
