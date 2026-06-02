# Handoff: Phase 2 API Client Split

Date: 2026-06-01

Branch: `design/v2-claude-design-handoff`

## Read First

- `RULES.md`
- `docs/architecture/ARCHITECTURE.md`
- `docs/architecture/PLAN.md`
- `docs/architecture/ChatStoreDebtMap.md`

## Current State

Phase 0 is complete.

- `docs/architecture/ChatStoreDebtMap.md` maps the major `ChatStore` buckets to canonical owners.
- No production Swift code was moved in Phase 0.

Phase 1 is complete.

- `NEARPrivateChatTests/PrivateChatCoreTests.swift` is now a shared test harness only.
- The 410 existing tests were split into owner-oriented files under `NEARPrivateChatTests/`.
- Xcode project membership was updated for the new test files.
- No production Swift behavior was moved in Phase 1.

Validation already run after Phase 1:

- `xcodebuild test -scheme NEARPrivateChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NEARPrivateChatTests/PrivateChatCoreTests/testAuthCallbackAcceptsAuthorizationCodeWithMatchingState`
- `xcodebuild test -scheme NEARPrivateChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NEARPrivateChatTests`
- `scripts/build-simulator.sh`
- `git diff --check`

Known preserved local stash:

- `stash@{0}: pre-phase0-real-render-ui-pass`
- Do not apply or drop it unless explicitly asked.

## Phase 2 Goal

Split the API surface so future feature extractions do not depend on one concrete mega-client.

Do not move feature behavior out of `ChatStore` yet. Phase 2 should create clean, fakeable API seams while preserving endpoint behavior.

## Non-Negotiables

- Preserve user-visible behavior.
- Do not add behavior to `ChatStore`.
- Do not start from broad UI cleanup.
- Do not introduce DB migrations.
- Do not run localhost.
- Do not create a branch with `codex/` prefix.
- New Swift files must be added to Xcode project membership.
- Keep `PrivateChatAPI` as a temporary compatibility facade where needed.
- Prefer narrow protocols over wrappers that still expose the mega-client.
- If a phase fails validation, stop and fix before proceeding to the next phase.

## Phase 2 Work Plan

1. Inventory `PrivateChatAPI`.

   Map methods to target domains before editing:

   - `AuthAPI`
   - `ConversationAPI`
   - `MessageAPI`
   - `ModelAPI`
   - `FileAPI`
   - `ShareAPI`
   - `SettingsAPI`
   - `BillingAPI`
   - `AttestationAPI`

2. Extract request infrastructure first.

   Create a small internal request core for:

   - base URL/config
   - authorization/header handling
   - JSON encode/decode
   - multipart/upload helpers
   - status/error normalization
   - stream request setup only if needed by domain clients

   Keep behavior byte-for-byte equivalent where possible.

3. Add domain protocols and concrete clients.

   Suggested target layout:

   - `NEARPrivateChat/Core/API/APIClient.swift`
   - `NEARPrivateChat/Core/API/AuthAPI.swift`
   - `NEARPrivateChat/Core/API/ConversationAPI.swift`
   - `NEARPrivateChat/Core/API/MessageAPI.swift`
   - `NEARPrivateChat/Core/API/ModelAPI.swift`
   - `NEARPrivateChat/Core/API/FileAPI.swift`
   - `NEARPrivateChat/Core/API/ShareAPI.swift`
   - `NEARPrivateChat/Core/API/SettingsAPI.swift`
   - `NEARPrivateChat/Core/API/BillingAPI.swift`
   - `NEARPrivateChat/Core/API/AttestationAPI.swift`

   Use existing names if the repo already has closer local conventions.

4. Keep `PrivateChatAPI` compiling as a facade.

   The safest first step is to let existing call sites keep using `PrivateChatAPI`, while `PrivateChatAPI` delegates to the new clients. Do not fan out call-site churn until the protocols are stable and tested.

5. Move tests by owner only where it increases clarity.

   The split test files are already in place. Add focused tests around protocol/domain behavior:

   - Auth request/auth callback tests in `NEARPrivateChatTests/Auth/AuthTests.swift`
   - model list/default route tests in `NEARPrivateChatTests/ModelCatalog/ModelCatalogTests.swift`
   - file upload/dispatch tests in `NEARPrivateChatTests/Files/FileTests.swift`
   - sharing tests in `NEARPrivateChatTests/Sharing/SharingTests.swift`
   - status/error/request-core tests in `NEARPrivateChatTests/API/APITests.swift`

6. Update `AppEnvironment` only when the seams are ready.

   Inject protocol-backed clients through app composition. If the call-site blast radius is too high, keep a compatibility adapter and document what Phase 4/5/6 will delete.

## Phase 2 Exit Criteria

- `PrivateChatAPI` no longer owns all domain behavior directly.
- Domain protocols exist for the listed API surfaces.
- New feature services can depend on protocols instead of the concrete mega-client.
- `PrivateChatAPI` remains only as a temporary compatibility facade where untouched code still needs it.
- `ChatStore` gains no new feature behavior.
- No Swift test file exceeds 1000 lines.
- No production Swift file crosses 1000 lines because of this phase.

## Phase 2 Validation

Run at minimum:

```sh
xcodebuild test -scheme NEARPrivateChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NEARPrivateChatTests
scripts/build-simulator.sh
git diff --check
```

Add narrower `-only-testing` runs while iterating, especially:

```sh
xcodebuild test -scheme NEARPrivateChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NEARPrivateChatTests/PrivateChatCoreTests/testAuthenticatedRequestsRejectWhitespaceSessionTokenBeforeNetwork
xcodebuild test -scheme NEARPrivateChat -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NEARPrivateChatTests/PrivateChatCoreTests/testWebSearchSourcesDropUnsafeSchemes
```

## Continue In Succession

After Phase 2 validates, proceed in this order from `PLAN.md`:

1. Phase 3: Persistence Split
2. Phase 4: Sharing Full Extraction
3. Phase 5: Files And Attachments Extraction
4. Phase 6: Projects Extraction
5. Phase 7: Conversation And Message Cache Extraction
6. Phase 8: Chat Send Pipeline Extraction
7. Phase 9: Council And Model Routing Extraction
8. Phase 10: Home Refactor
9. Phase 11: Setup Split
10. Phase 12: Chat UI Split
11. Phase 13: Agent And Account Split
12. Phase 14: Security And Export Cleanup
13. Phase 15: Delete Or Crush `ChatStore`

For each phase:

- Start by reading the relevant test file group created in Phase 1.
- Move one responsibility bucket only.
- Add or move tests next to the owner.
- Update `docs/architecture/PLAN.md` implementation status.
- Run validation before continuing.
- Leave a short handoff note if stopping mid-phase.

## Architecture Review Bar

Block the phase if it:

- adds unrelated methods to `ChatStore`
- adds feature-specific branches to shared/core code
- creates protocol names without making dependencies fakeable
- moves code but leaves ownership equally confusing
- adds a thin wrapper around `PrivateChatAPI` without reducing direct mega-client dependency
- adds optional/cast-heavy contracts instead of clear typed boundaries
- pushes any Swift file over 1000 lines

The right move is not cosmetic line shuffling. The right move is making one owner obvious enough that the next phase can delete work from `ChatStore`.
