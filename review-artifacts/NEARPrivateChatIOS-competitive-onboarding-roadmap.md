# NEAR Private Chat iOS Competitive And Onboarding Roadmap

Date: 2026-05-24
Scope: integrated product/design/code review using the local `NEARPrivateChatIOS` source, the onboarding review, and the supplied competitive audit.

Note: external competitor observations are treated as supplied benchmark input. This pass cross-checks NEAR Private Chat against the current local code and updates stale items in the draft.

## Executive Take

NEAR Private Chat is not short on features. It is already strong on projects, sharing, model routing, LLM Council, IronClaw, imports/exports, and especially TEE attestation. The competitive weakness is not capability depth; it is interaction clarity.

The new screenshot pass sharpens the diagnosis: the app reads as three products fighting for the same first screen: Private Chat, IronClaw Agent, and Project Context. All three matter, but the iOS app should make Ask feel primary, then progressively disclose Agent and Project power once a user has context.

The product can reach peer parity quickly by tightening five surfaces:

1. Home: one primary Ask action, fewer visible concepts, cleaner project metadata, progressive disclosure for Agent/Context.
2. Composer: fewer source concepts, stronger send/stop control, clearer attachment/source state.
3. Model picker: less chip noise, clearer Models vs Council split, friendlier plan-lock language.
4. Action menus: grouped overflow menus, destructive zones, undo for reversible actions.
5. Empty/settings states: setup-aware prompt chips, first-action prompts, developer plumbing behind disclosure.

The category-winning move is still attestation. No peer in the benchmark has a comparable verifiability primitive. NEAR should turn attestation from a hidden sheet into a persistent trust system across model chips, message bubbles, exports, and shared links.

## Current-State Corrections To The Supplied Audit

Some competitive-audit items are already improved in the current tree:

- Permanent conversation delete now routes through a global confirmation dialog with "Archive Instead" and "Delete Permanently".
  - `NEARPrivateChat/AppShellView.swift` lines 37-54.
  - `NEARPrivateChat/ChatStore.swift` lines 1663-1678.
- "Run Setup Again" now calls back into `RootView` and immediately reopens setup.
  - `NEARPrivateChat/NEARPrivateChatApp.swift` lines 48-52.
  - `NEARPrivateChat/AppShellView.swift` lines 4171-4178.
- `Saved links` is back in the composer menu.
  - `NEARPrivateChat/AppShellView.swift` lines 6411-6434 and 6529-6531.
- The model picker already has sections and an LLM Council card, but not true Models/Council tabs.
  - `NEARPrivateChat/AppShellView.swift` lines 1556-1678.
- Empty chat still lacks authoring chips, but the Agent workspace does have task suggestions.
  - `NEARPrivateChat/AppShellView.swift` lines 4852-4880.
  - `NEARPrivateChat/AppShellView.swift` lines 5029-5057.
- Privacy manifest now exists and declares no tracking or collected data, but there is no telemetry/analytics scaffolding in source.
  - `NEARPrivateChat/PrivacyInfo.xcprivacy`.
- There are no App Intents, WidgetKit, ActivityKit, WatchKit, or telemetry files in the app tree.
- Several earlier engineering audit findings now appear fixed:
  - Conversation loads use a task plus generation guard: `NEARPrivateChat/ChatStore.swift` lines 106-107 and 2130-2178.
  - Cached messages are shown optimistically and then refreshed/merged from remote: `NEARPrivateChat/ChatStore.swift` lines 2161-2186.
  - Projects/messages/conversation caches now use file-backed protected storage with UserDefaults fallback: `NEARPrivateChat/ChatStore.swift` lines 3617-3634 and 5905-5922.
  - Plain file upload reads are detached from the main actor: `NEARPrivateChat/PrivateChatAPI.swift` lines 169-185.
  - Public/shared readable fetch retries unauthenticated on 401/403: `NEARPrivateChat/PrivateChatAPI.swift` lines 608-617.

So the revised gap is not "delete has no confirmation" or "setup rerun is broken"; it is "deletes still need undo/receipts," "setup rerun is not prefilled/account-scoped," and "source modes remain too complex despite Saved links being restored."

## Updated Competitive Scorecard

| Dimension | Current NEAR PC iOS | Competitive Gap | Priority |
| --- | --- | --- | --- |
| Onboarding | OAuth, shared link, first-run setup, starter projects | Setup profile saved but not loaded; completion global; wizard asks about advanced concepts too early | P1 |
| Privacy telemetry | Privacy manifest says no tracking/data collection; no analytics code found | No measurement strategy for roadmap success criteria | P0 |
| Home | Command card plus projects and recents | Reads as Ask, Agent, and Context competing; too many first-screen concepts; three primary affordances | P1 |
| Composer | Two-row composer, paperclip, source menu, Research toggle, brand send when active | Source mode + Research is still two-axis; send is not a morphing mic/send/stop control; no focus chip row | P1 |
| Model picker | Sections, search, Council card, plan chips | Too many chips; no Models/Council tabs; unfriendly "locked hidden" language; no relative cost | P1 |
| Tools/sources | Auto/Web/Saved links/Project/Files plus Research | Powerful but cognitively heavier than peer focus modes | P1 |
| Projects | Instructions, memory, files, notes, links, scoped chats | No icon/color; taxonomy still too many terms; no project default tools/source mode | P2 |
| Agent | Dedicated IronClaw sheet with mission control when connected | Strong differentiator, but less in-thread progress visibility than peer agent patterns | P2 |
| Action menus | Chat overflow and action menus expose 11-13 items | Actions are flat, destructive actions sit too near everyday actions, undo is missing | P1 |
| Sharing | Public links, invites, org patterns, share groups, write access | Public enable is one button; no preview/anonymize/attestation seal/undo for revocation | P2 |
| Files/vision | Uploads, library, PDF-to-text, imports | No live preview/canvas; PDF structure loss; no image-first library experience | P3 |
| Voice/live | Not present | Largest peer feature absence, but lower priority than core interaction and attestation | P3 |
| Settings | Rich account sheet with diagnostics, billing, NEAR Cloud, IronClaw | Too much plumbing visible by default; developer options need disclosure | P2 |
| Verifiability | TEE attestation sheet exists | Field-leading capability but hidden and not attached to messages/models/shares | P0 |
| Empty states | Empty chat logo/subtitle; generic content-unavailable rows | Needs setup-aware prompt chips and first actions | P1 |
| Visual identity/accessibility | Brand blue, dark command card, SF Symbols | Brand blue is overloaded; small grey metadata likely needs WCAG AA contrast pass; attestation needs distinct visual language | P2 |
| Memory | Project memory only | No editable global memory card | P3 |
| iOS system surfaces | No App Intents/Widgets/Live Activities found | Misses standard iOS entry points and unique attestation surfaces | P2 |
| Mac path | iPhone-only target and portrait-only orientation; Catalyst disabled | Mac could be a strong power-user follow-up after iOS quality; iPad-specific work is deferred | Later |
| Engineering hygiene | Several P1s fixed, but monolithic files, sparse tests, release config, streaming resilience remain | Needs Sprint 0 budget before large visual/product work | P0 |

## Onboarding Synthesis

The onboarding review found that setup is meaningful: it changes `webSearchEnabled`, source mode, research mode, selected model, Council selection, and starter projects.

Relevant source:
- `NEARPrivateChat/NEARPrivateChatApp.swift` lines 92-174.
- `NEARPrivateChat/Models.swift` lines 374-489.
- `NEARPrivateChat/ChatStore.swift` lines 1144-1175.

The weak spots are:

- Setup asks about internal concepts before the user has seen the app.
- `UserSetupStorage.profileKey` is saved but never loaded.
- Setup completion is global instead of account-scoped.
- Skip silently saves defaults without explaining them.
- Build Agents can select IronClaw behavior before hosted readiness is clear.
- Council can be requested even when the available model lineup may not support it.

Recommended target:

1. Goal-first setup: Private Chat, Research, Project Files, Agent Work.
2. A "Recommended defaults" preview card before Finish.
3. Readiness-aware gating for Council, IronClaw hosted workstation, NEAR Cloud, and billing.
4. A setup-complete landing card on home with next actions.
5. Prompt chips derived from use case and selected project.

## Product Strategy

### Parity Moves

These make NEAR feel as polished as the field:

- Home information diet: one primary Ask action, 8 or fewer visible concepts, hidden zero-count metadata, and progressive disclosure for Agent/Context.
- Morphing composer trailing control: mic when empty, send when ready, stop while streaming.
- Single-axis Focus row: Auto, Web, Files, Links, Research.
- Model picker tabs: Models and Council.
- Cleaner plan-lock copy: "Upgrade for 29 more models" instead of "29 locked hidden".
- Project icon/color and hidden zero-count metadata.
- Grouped overflow/action menus with destructive zones and undo for reversible actions.
- Consistent product vocabulary: Project, Sources, Files, Notes, Instructions.
- Empty-state prompt chips.
- Developer settings disclosure.
- App Intents and shortcuts for verified chat, selected text, and shared links.
- Mac path after iOS quality is high; no iPad-specific work in the near-term iOS polish track.

### Category Moves

These make NEAR meaningfully different:

- Privacy-preserving telemetry that is explicit, minimal, and user-visible.
- Per-message attestation chips.
- Signed/verified model badge in chat header.
- Persistent attestation freshness indicator.
- Verifiable transcript export.
- Open-source transcript verifier plus public drag-and-drop verification page.
- Attestation education: "proof, not a promise" explainer and first-run guidance.
- Public shared chats with attestation seal.
- Private + Verified mode that only permits attested routes.
- Signed deletion receipts for permanent deletes.
- Council disagreement report as a shareable/exportable artifact.
- Live Activity / widget / watch glance for active-session attestation freshness.

## Design Review Addendum

Detailed screenshot findings are captured in `review-artifacts/NEARPrivateChatIOS-design-review-addendum.md`. The most important incorporated changes are:

- Treat the home screen as an information diet problem. The first screen should sell one action, Ask, then reveal Agent and Project capabilities after setup choice or first use.
- Make status chips read as a system: `Noun: state`, for example `Privacy: verified`, `Web: on`, `Sources: 1`.
- Move source/link/file chips into an attachment shelf above the composer.
- Standardize menus into Navigate, Edit, Export, Organize, and Destructive groups.
- Make public sharing explicit with preview, expiry, invite-first alternative, and attestation seal.
- Put developer plumbing behind disclosure in Account.
- Use one taxonomy: Project, Sources, Files, Notes, Instructions.
- Reserve brand blue for primary action and give attestation its own verified accent.

## Implementation Roadmap

### Packet -1 - Privacy-Preserving Measurement Strategy

Priority: P0

Decision:
Use local differential-privacy counters with on-device aggregation. Do not collect prompts, responses, file names, source URLs, account identifiers, transcript IDs, raw model outputs, or raw event streams. Upload only noisy aggregate counters from a documented event schema, behind a user-visible privacy setting. If server-side rollups are added later, require k-anonymous reporting thresholds before dashboards expose a metric.

Why:
The roadmap has success criteria, but the current app has no way to measure them without violating the product promise. The privacy manifest currently declares no tracking or collected data, and source search found no analytics scaffolding. That is cleaner than quiet telemetry, but it means Sprint 1 would fly blind unless measurement is decided first.

Current state:
- `NEARPrivateChat/PrivacyInfo.xcprivacy` declares `NSPrivacyTracking = false` and no collected data types.
- No telemetry/analytics files or App Metrics scaffolding were found in the local app tree.

Build:
- Add `PrivateTelemetryPolicy.md` and in-app Privacy Settings copy.
- Add `TelemetryEvent` enum limited to product-shape events:
  - setup_goal_selected
  - setup_completed_or_skipped
  - focus_mode_changed
  - prompt_chip_used
  - attestation_chip_tapped
  - attestation_refresh_succeeded_or_failed
  - model_picker_tab_opened
  - share_preview_opened
  - stream_reconnected
  - generic error category, never raw error bodies
- Aggregate counters on device by day/version/profile bucket.
- Add local differential-privacy noise before upload.
- Add a single user setting: "Share private usage statistics", defaulting to off until legal/product explicitly chooses opt-in vs opt-out.
- Add a local-only diagnostics export so testers can inspect counters without upload.
- Update `PrivacyInfo.xcprivacy` only if/when uploads are enabled.

Acceptance criteria:
- The app can answer whether onboarding, composer, model picker, and attestation changes are being used without seeing content.
- The user can inspect and disable telemetry.
- The telemetry schema is public and excludes content by construction.
- No analytics network call ships until privacy copy and manifest are updated.

Tests:
- Unit test that forbidden fields cannot be encoded in telemetry payloads.
- Unit test DP/noise path and local aggregation.
- Snapshot test Privacy Settings copy.

### Packet 0 - Attestation As A System

Priority: P0

Why:
Attestation is the strongest differentiator and should be visible before voice or large visual redesign work.

Current state:
- Security sheet fetches and displays gateway/model attestation.
- The chat toolbar has a security button.
- Messages and exports do not carry attestation state.

Relevant source:
- `NEARPrivateChat/AppShellView.swift` lines 1345-1349.
- `NEARPrivateChat/AppShellView.swift` lines 4661-4768.
- `NEARPrivateChat/ChatStore.swift` lines 2057-2073.
- `NEARPrivateChat/PrivateChatAPI.swift` lines 414-451.

Build:
- Add `AttestationStatus` model: unknown, valid, stale, unavailable, mismatch.
- Add `verifiedGreen` color token distinct from brand blue.
- Add header shield with freshness: `<2m`, `<1h`, `stale`.
- Add tiny shield chip on assistant messages produced by attested NEAR Private routes.
- Add verified checkmark to model chip when selected model is covered by current attestation.
- Replace bare counts like "Model attestations: 1" with human-readable state such as "1 of 1 models verified" or "`GLM-5.1-FP8` verified via TEE."
- Tap any shield to open Security, ideally with selected model/message context.
- Add "Verified mode" composer/header toggle later, after status model lands.

Acceptance criteria:
- A fresh attestation is visible without opening overflow menus.
- Assistant bubbles from attested NEAR Private routes show a shield.
- NEAR Cloud/external/non-attested routes show neutral/unavailable state, not false confidence.
- Changing models invalidates or refreshes the relevant attestation state.
- Security sheet can still show raw JSON for expert users.

Tests:
- Unit test freshness classification.
- Unit test selected model coverage.
- Snapshot/UI test message chip visibility for attested vs non-attested routes.

### Packet 0b - Attestation Education Layer

Priority: P0

Why:
Shield chips and green badges are only valuable if users understand them. The UX should explain that attestation is cryptographic evidence about the route/model, not a generic privacy promise.

Build:
- Add a one-screen explainer reachable from every shield tap:
  - "Proof, not a promise."
  - What was verified.
  - What was not verified.
  - What stale or unavailable means.
  - Why external/NEAR Cloud/IronClaw routes may show a different status.
- Add a short "What does this mean?" link to the Security sheet before raw hashes/nonces.
- Add a 60-second first-run carousel after setup for users who chose Private Chat, Research, Agent Work, or Verified mode:
  - "Private route"
  - "Verified model"
  - "Exportable proof"
- Add inline tooltips on the first three message-shield taps.
- Add "Learn how to verify this transcript" to export/share surfaces once signed exports exist.

Acceptance criteria:
- First shield tap teaches the concept without dumping raw JSON.
- Expert users can still reach raw JSON.
- Copy never overclaims that attestation verifies truthfulness, factuality, or safety of an answer.

### Packet 0c - Open Verifier Ecosystem

Priority: P0/P1

Why:
A signed export is only category-defining if third parties can verify it outside the app. This moves NEAR from "trust our app UI" to "verify our artifact format."

Build:
- Define `near-private-chat-transcript-v1.json`:
  - transcript hash
  - message hashes
  - model IDs
  - route metadata
  - attestation nonce/hash
  - signing algorithm
  - signature
  - export timestamp
- Add a tiny verifier package:
  - npm CLI: `npx near-private-chat-verify transcript.json`
  - Python CLI: `python -m near_private_chat_verify transcript.json`
- Add a public static verification page where a user can drag in a signed export and verify locally in browser.
- Add fixtures generated from test transcripts.
- Document the threat model and what the verifier cannot prove.

Acceptance criteria:
- A signed export can be verified without the iOS app.
- Verification runs locally without uploading transcript content.
- Invalid/tampered transcript fixtures fail.
- Public docs are clear enough for legal/finance/security reviewers.

### Packet A - Composer To Industry Standard

Priority: P1

Current state:
- Composer has a paperclip, source-mode menu, Research toggle inside menu, and send/stop button.
- Source modes are Auto, Web, Saved links, Project, Files plus separate Research.

Relevant source:
- `NEARPrivateChat/AppShellView.swift` lines 6375-6488.
- `NEARPrivateChat/AppShellView.swift` lines 6519-6531.
- `NEARPrivateChat/ChatStore.swift` lines 300-330 and 5530-5578.

Build:
- Set composer hierarchy:
  - row 1: input plus trailing send/stop
  - row 2: attachment, Focus chip/row, and active project/source state
- Replace source-mode menu as primary control with a horizontal Focus row under or above composer:
  - Auto
  - Web
  - Files
  - Links
  - Research
- Treat Focus as single-axis. Research becomes a focus state, not a second toggle.
- Move detailed descriptions into a long-press/popover or sheet:
  - Auto: "Use files and web when helpful."
  - Web: "Use live web first."
  - Files: "Use project and attached files."
  - Links: "Use saved source links."
  - Research: "Use live sources, project context, and citations."
- Add morphing trailing control:
  - empty: mic/voice placeholder once voice exists; until then disabled send icon is fine
  - non-empty/attachments: filled brand circle send
  - streaming: stop icon
- Add attachment shelf above composer for pending files and source links so paperclip/link state is visible.
- Reuse the Agent workspace context affirmation pattern in chat: project, sources, notes, and route in one quiet line.

Acceptance criteria:
- User can select exactly one Focus state.
- Research is no longer a separate hidden axis.
- NEAR Cloud route clearly disables web/tool states or says "Cloud route, no NEAR web tools."
- Source-mode tests assert request behavior for each focus.
- Send/stop control does not shift layout.
- Source and file chips no longer sit in the same visual row as the text-input affordance.

### Packet B - Onboarding Upgrade

Priority: P1

Current state:
- Setup is compact and functional, but dense.
- Profile is saved but not loaded.
- Completion is global.

Relevant source:
- `NEARPrivateChat/NEARPrivateChatApp.swift` lines 40-90 and 92-174.
- `NEARPrivateChat/Models.swift` lines 492-505.
- `NEARPrivateChat/ChatStore.swift` lines 1144-1175.

Build:
- Reorder unauthenticated entry:
  - OAuth and shared-link open are primary.
  - Session token moves behind "More sign-in options" or Developer mode.
- Lead with verifiability in auth copy, not generic private-cloud positioning.
- Add account-scoped setup storage.
- Add `UserSetupStorage.load(for:)`.
- Pre-fill setup from saved profile or current store state.
- Add `AppSetupPlan` preview before Finish:
  - Model route
  - Focus/source behavior
  - Starter project
  - Agent/Council state
  - Expected first action
- Add setup-complete card on home with actions:
  - Start chat
  - Add sources/files
  - Connect agent
  - Change setup
- Add setup-derived prompt chips in empty chat.

Acceptance criteria:
- Rerun setup edits existing choices.
- Signing into a different account does not inherit the previous account's completed flag.
- Skip shows what defaults were chosen or lands on a defaults card.
- Build Agents setup distinguishes phone-local IronClaw Mobile from hosted workstation readiness.
- Shared-link entry stays available without requiring a full account-first mental model.

### Packet C - Model Picker Collapse

Priority: P1

Current state:
- Picker has sections and a Council card.
- Summary exposes internal "locked hidden" / "Legacy hidden" language.

Relevant source:
- `NEARPrivateChat/AppShellView.swift` lines 1556-1678.
- `NEARPrivateChat/AppShellView.swift` lines 1680-1753.
- `NEARPrivateChat/AppShellView.swift` lines 1755-1851.
- `NEARPrivateChat/ChatStore.swift` lines 489-526 and 4446-4599.

Build:
- Add segmented tabs: Models and Council.
- In Models tab:
  - Show two chips max per row: verified/private state and plan/cost state.
  - Move provider, context window, web capability, and route details into an expander.
  - Replace hidden plumbing copy with "Upgrade for N more models."
  - Add relative cost labels where data exists: Free, Included, Higher cost, External key.
- In Council tab:
  - Explain parallel answers and synthesis.
  - Show selected lineup as reorderable/clearable rows.
  - Add "Use default council" and "Single model" actions.

Acceptance criteria:
- No user-facing "locked hidden" or "Legacy hidden" copy.
- Council setup is not mixed into every model row unless the row is in selection mode.
- Plan restrictions remain enforced.
- Search works in Models tab.
- The label "Web on" is scoped clearly when it means model capability vs current chat state.

### Packet D - Project Visual Lift And Taxonomy

Priority: P2

Current state:
- Projects have name, instructions, memory, links, files, notes, conversation IDs.
- Project list uses folder glyphs and metadata strings.

Relevant source:
- `NEARPrivateChat/Models.swift` lines 1353-1386.
- `NEARPrivateChat/AppShellView.swift` lines 146-204.
- `NEARPrivateChat/AppShellView.swift` lines 2900-3275.
- `NEARPrivateChat/ChatStore.swift` lines 1243-1251 and 5579-5631.

Build:
- Add project icon and color fields with defaults.
- Hide zero-count metadata.
- Render project metadata as compact icon/count pairs instead of comma-separated strings.
- Visually separate system collections like All Chats, Shared With Me, and Archived from user projects.
- Add per-project default Focus/source mode and default tools.
- Collapse naming into one workspace term plus four content terms:
  - Project
  - Sources
  - Files
  - Notes
  - Instructions
- Rename or absorb "Context", "Library", "Saved", and "Guide" into those terms.
- Verify QA seed names such as "IronClaw Phone QA" cannot ship in production fixtures.

Acceptance criteria:
- Project list is visually scannable without reading every title.
- Selecting a project can set default Focus unless user overrides.
- Empty project surfaces show first actions: Add file, Add link, Add note.
- No production project row shows zero-count metadata.

### Packet E - Safety, Undo, And Receipts

Priority: P2

Current state:
- Conversation permanent delete has confirmation.
- Archive, move, share revocation, file delete, and group delete mostly show banners but not undo.

Relevant source:
- `NEARPrivateChat/AppShellView.swift` lines 37-54.
- `NEARPrivateChat/ChatStore.swift` lines 1663-1678.
- `NEARPrivateChat/ChatStore.swift` lines 1735-1753.
- `NEARPrivateChat/ChatStore.swift` lines 2011-2049.
- `NEARPrivateChat/ChatStore.swift` line 1465.

Build:
- Add undo toast infrastructure for:
  - archive
  - move to project
  - remove project file
  - disable public link
  - remove share access
  - delete remote file, if API supports restore or delayed commit
- Keep permanent delete behind confirmation.
- Add signed deletion receipt if backend supports it, or prepare local receipt model with pending API integration.

Acceptance criteria:
- Archive can be undone for a short window.
- Share revocation has clear confirmation/undo language.
- Permanent delete returns or stores a receipt when API supports it.

### Packet F - Empty-State Authoring

Priority: P1

Current state:
- Empty chat is a wordmark/subtitle only.
- Some secondary sheets use generic `ContentUnavailableView`.

Relevant source:
- `NEARPrivateChat/AppShellView.swift` lines 4852-4880.
- `NEARPrivateChat/AppShellView.swift` lines 208-214.
- `NEARPrivateChat/AppShellView.swift` lines 3041, 3087, 3178, 3993.

Build:
- Add setup/project-aware prompt chips:
  - Private Chat: summarize, draft, compare.
  - Research: research with dated sources, compare sources, make memo.
  - Agent Work: review repo, plan feature, QA checklist.
  - Projects: ask from files, add source link, save note.
- Replace the empty new-chat logo-only state with 3-4 rotating "Try..." prompts.
- Add first-action buttons to empty File Library and Shared With Me.
- Mention upload constraints where helpful: 10 MB cap, PDFs converted to readable text.
- Prefer full-height file/library management sheets so blurred chat content does not compete with the file workflow.

Acceptance criteria:
- New user can start with one tap from an empty chat.
- Prompt chips populate composer without auto-sending.
- Empty secondary states teach the first action.
- Shared With Me empty/loaded states clearly distinguish content owned by someone else from the user's editable chats.

### Packet G - Sharing Trust Pass

Priority: P2

Current state:
- Public link, invites, org patterns, share groups, and write permission exist.
- Public link enablement is a single button with no preview/anonymize/seal step.

Relevant source:
- `NEARPrivateChat/AppShellView.swift` lines 2027-2205.
- `NEARPrivateChat/ChatStore.swift` lines 1827-2049.
- `NEARPrivateChat/PrivateChatAPI.swift` lines 301-392.

Build:
- Add a pre-enable confirmation panel for public links:
  - What recipients can see
  - Whether author metadata is included
  - Whether attestation seal is included
  - Copy preview
- Add link expiry options.
- Add "Invite specific people" as a visible secondary path next to public link creation.
- Add attestation seal to shared previews.
- Add share revocation undo/confirmation.
- Preserve shared-link-first onboarding path.

Acceptance criteria:
- Public link enable has explicit informed consent.
- Shared preview communicates read/write state and verified status.
- Signed-out shared link flow is not blocked by generic onboarding.
- A shared chat clearly indicates when the user is viewing someone else's content and whether they can edit.

### Packet H - Settings Hygiene

Priority: P2

Current state:
- Account sheet exposes endpoint, callback, auth scheme, setup, diagnostics, chat settings, billing, NEAR Cloud, IronClaw bridge, imports, share groups, sign out.

Relevant source:
- `NEARPrivateChat/AppShellView.swift` lines 4115-4434.

Build:
- Move endpoint/callback/auth behind a Developer disclosure.
- Collapse diagnostics into one row with last status and "Run diagnostics."
- Move IronClaw bridge into Agent settings or the Agent sheet.
- Make NEAR Cloud key an advanced route setting.
- Keep Billing visible but concise.
- Keep Run Setup Again visible, but clarify that it updates preferences rather than wiping account data.
- Convert multi-line diagnostics explanation into tooltip/help copy.

Acceptance criteria:
- Default account sheet reads like a consumer settings page.
- Developer plumbing is still accessible in debug/advanced mode.
- Diagnostics output remains available.
- A normal user can scan Account without seeing endpoint/callback/auth plumbing.

### Packet I - Visual System Pass

Priority: P2

Current state:
- Brand blue is used for many active, verified, selected, and primary states.
- Attestation does not have its own visual language.

Relevant source:
- Broad use of `Color.brandBlue` across `AppShellView.swift`.
- Security surfaces at `NEARPrivateChat/AppShellView.swift` lines 4661-4768.

Build:
- Reserve brand blue for primary actions and navigation.
- Add verified green or verified violet for attestation and trust.
- Add a small visual grammar:
  - blue = action
  - green/violet = verified
  - grey = neutral
  - red = destructive/error
- Run Dynamic Type and WCAG AA contrast checks.
- Increase contrast for project metadata, segmented active tabs, and sheet helper text.
- Add a clearer typography ladder for section headers and in-sheet headings.
- Standardize sheet hierarchy: drag handle, top-left Done, centered title, optional top-right action.
- Rework hero/card typography enough to avoid generic-tech-blue sameness.

Acceptance criteria:
- Security/verified states are visually distinguishable from generic selected states.
- Primary CTA is easier to identify.
- No text truncation in common Dynamic Type sizes.
- Metadata text meets WCAG AA at the displayed size.

### Packet J - Voice Mode

Priority: P3

Current state:
- No visible live voice mode in source.

Build:
- Full-screen voice surface with interrupt/stop.
- Start with speech-to-text/text-to-speech if backend route exists.
- Extend "Verified Voice" only if voice route can preserve attested model guarantees.

Acceptance criteria:
- Voice does not compromise the verified/private story.
- If verification is unavailable, UI says so clearly.

### Packet K - Global Memory

Priority: P3

Current state:
- Project memory exists; global editable memory does not.

Relevant source:
- `NEARPrivateChat/Models.swift` lines 1353-1386.
- `NEARPrivateChat/AppShellView.swift` lines 3220-3237.
- `NEARPrivateChat/ChatStore.swift` lines 1243-1251.

Build:
- Add global memory card in Account or a dedicated Memory screen.
- Keep project memory separate from global memory.
- Add "what is remembered" transparency and delete controls.

Acceptance criteria:
- User can view/edit/delete global memory.
- Prompts show whether global memory and/or project memory is active.

### Packet L - Council Disagreement Artifacts

Priority: P1/P2

Why:
LLM Council should not only synthesize consensus. The differentiated product is showing where strong models disagree, especially for high-stakes research, legal, financial, medical, security, and product decisions.

Current state:
- Council runs multiple models, shows per-model answers, and synthesizes.
- The synthesis prompt asks for disagreements, but disagreement is not a durable first-class artifact.

Relevant source:
- `NEARPrivateChat/AppShellView.swift` lines 1001-1048.
- `NEARPrivateChat/ChatStore.swift` lines 2523-2749.

Build:
- Add `CouncilDisagreementReport` generated after successful Council runs:
  - consensus claims
  - disagreements
  - model-specific minority reports
  - unsupported claims
  - recommended follow-up checks
- Add a collapsed "Disagreements" panel above or below synthesis.
- Add export/share for "Council report" as JSON/PDF/TXT.
- For verified routes, include attestation status per model answer in the report.

Acceptance criteria:
- Users can inspect dissent without reading every full model answer.
- Exported report separates consensus from disagreement.
- The report does not falsely imply majority vote equals truth.

### Packet M - iOS System Surfaces

Priority: P2

Why:
These are cheaper than voice and make the app feel native. They also let attestation become a system-level trust signal rather than an in-app-only badge.

Current state:
- No `AppIntent`, `WidgetKit`, `ActivityKit`, or WatchKit files were found.
- App intents metadata extraction currently warns that no AppIntents dependency exists during build.

Build:
- App Intents / Shortcuts:
  - Start a verified chat.
  - Ask NEAR Private about selected text.
  - Open shared link in NEAR Private Chat.
  - Start research mode in active project.
- Live Activities:
  - Active verified session: `Verified · last attested 2m ago`.
  - Active long-running IronClaw run: status/progress, no prompt content.
- Widgets:
  - Recent/pinned chats.
  - Pinned project quick action.
  - Attestation freshness.
- Apple Watch:
  - Active-session attestation glance only.
  - Skip Vision Pro for now.

Acceptance criteria:
- No widget/live-activity surface leaks prompt or transcript content.
- Shortcuts can start flows without requiring the app to expose internal route names.
- Live Activity and Watch surfaces use attestation status only when current and route-covered.

### Packet N - Mac Path After iOS

Priority: Later

Why:
Mac would be a strong power-user surface for projects, files, Council disagreement reports, verifier workflows, and IronClaw sessions. It should not compete with the immediate iOS quality work. iPad-specific work is explicitly deferred for now.

Current state:
- `TARGETED_DEVICE_FAMILY = 1`.
- `Info.plist` supports portrait only.
- Mac Catalyst is disabled.

Relevant source:
- `NEARPrivateChat.xcodeproj/project.pbxproj` lines 380-423.
- `NEARPrivateChat/Info.plist` lines 44-47.

Build later:
- Finish the iPhone-first information architecture, composer, attestation, model picker, menus, empty states, and visual system first.
- After iOS quality is stable, evaluate native macOS SwiftUI vs Catalyst.
- Reuse cleaned iOS concepts:
  - Project sidebar
  - Active chat
  - Project/Sources/Files/Notes/Instructions inspector
  - Security and attestation inspector
  - Council report workspace
- Treat Mac as a power-user extension of the verified/private workflow, not as a way to preserve current density.

Acceptance criteria:
- No Mac planning blocks iOS P0/P1 design fixes.
- The Mac concept inherits the cleaned iOS taxonomy and attestation system.
- Portrait iPhone behavior remains unchanged.

### Packet O - Engineering Hygiene Sprint

Priority: P0

Why:
The product roadmap should not bury correctness and maintainability. Several earlier P1 issues are now fixed, but there are still enough open engineering risks that Sprint 1 needs a hygiene lane.

Confirmed fixed from earlier audit:
- Conversation load race now has task/generation guards.
- Cached messages now refresh/merge instead of permanently masking server truth.
- Projects/messages/conversation cache now uses file-backed protected storage.
- Plain upload file reads are detached.
- Public/shared readable endpoints retry unauthenticated on stale 401/403.
- IronClaw unused SSE consumer appears removed.
- Privacy manifest exists.

Still open / needs verification:
- Test coverage remains thin relative to feature surface.
- `AppShellView.swift` is about 7,221 lines and `ChatStore.swift` about 6,148 lines.
- Release signing still has empty `DEVELOPMENT_TEAM`.
- iPhone-only and portrait-only config remains; this is acceptable for the near-term iOS-first push, but should be documented as a deliberate choice.
- Raw shared ID parser and setup storage need tests.
- Share/file/group destructive actions need undo/confirmation consistency.
- Docs can drift as fast as the app changes.

Build:
- Add protocol seams for `PrivateChatAPI`, `IronclawAPI`, persistence, telemetry, and attestation status.
- Add tests for:
  - setup storage/account scoping
  - focus/source routing
  - stream truncation and reconnect behavior
  - shared-link stale-token fallback
  - conversation switching/load generation
  - Council report generation
- Split files gradually:
  - `ChatStore+Setup.swift`
  - `ChatStore+Sources.swift`
  - `ChatStore+Sharing.swift`
  - `ChatStore+IronClaw.swift`
  - `ChatStore+Council.swift`
  - `AppShell+Composer.swift`
  - `AppShell+ModelPicker.swift`
  - `AppShell+ProjectContext.swift`
  - `AppShell+Security.swift`
- Add release-readiness checklist in repo docs.

Acceptance criteria:
- New packets come with focused tests.
- No new feature packet increases `AppShellView.swift` or `ChatStore.swift` by more than a small agreed budget unless it is extracting code.
- Release config gaps are tracked explicitly.

### Packet P - Mobile Streaming, Sync, And Performance Budgets

Priority: P0/P1

Why:
Mobile chat fails in ways web chat often does not: cell handoff, backgrounding, lock screen, stream drops, and multi-device edits. These need semantics before composer/model polish drives more usage.

Build:
- Performance budgets:
  - cold start to first cached frame
  - sign-in to home interactive
  - chat switch to first transcript paint
  - time to first streamed token
  - sustained stream UI update rate
  - model picker open time
- Add `os.Logger`/signposts for local performance measurement without content telemetry.
- Cell-network streaming resilience:
  - detect stream interruption
  - mark assistant message as reconnecting
  - fetch latest conversation items by conversation/response ID after reconnect
  - avoid duplicate text on resume
  - clear "still streaming" state on app foreground if server completed
- Multi-device semantics:
  - show sync state when remote messages changed
  - detect write conflicts if web and iOS both stream into same conversation
  - present "remote update available" or branch/copy-and-continue instead of silently overwriting

Acceptance criteria:
- Airplane mode/cell handoff/background tests do not leave permanent phantom streaming messages.
- Chat opened on web and iOS does not silently lose one side's turn.
- Performance regressions are visible during development.

### Packet Q - Information Density Reduction

Priority: P1

Why:
The home screen currently introduces too many concepts before the user sends a first message. The app should stop making Ask, Agent, and Context compete equally on first launch.

Build:
- Make Ask the only primary home CTA.
- Remove or demote the toolbar plus button if Ask is already present.
- Hide Agent and Context entry points on first run unless setup selected agent/builder behavior.
- Collapse status chips to one grammar: `Noun: state`.
- Hide zero-count project metadata.
- Use compact symbol/count metadata for non-zero project stats.
- Separate system collections from user projects.
- Add a short setup-complete card with next action, then dismiss it once used.

Acceptance criteria:
- Home shows 8 or fewer major concepts before first tap.
- A new user can identify the primary action in under a second.
- No project row shows zero-count metadata.
- Agent readiness is either tappable or not shown as a status pill.

### Packet R - Overflow And Action Menu Surgery

Priority: P1

Why:
Current overflow/action menus are long, flat, and mix destructive actions with ordinary navigation. This creates both cognitive load and safety risk.

Build:
- Standardize action groups:
  - Navigate
  - Edit
  - Export
  - Organize
  - Destructive
- Use separators between groups.
- Hide actions that do not apply to the current context.
- Promote Share to a header affordance where it is a common action.
- Rename "Copy & Continue" to "Branch from here" or "Duplicate chat."
- Keep Delete red and confirm-only.
- Add undo toast for archive, move, link revocation, and file removal where reversible.

Acceptance criteria:
- Chat overflow and chat action menu use the same taxonomy.
- Destructive actions are visually isolated.
- Delete cannot be triggered without confirmation.
- Reversible actions show undo.

### Packet S - Naming Consolidation

Priority: P2

Why:
Sources, Library, Files, Saved, Context, and Guide currently describe overlapping concepts. Users should not need to learn six labels for two or three kinds of material.

Build:
- Adopt one workspace term and four content terms:
  - Project
  - Sources
  - Files
  - Notes
  - Instructions
- Map old terms:
  - Context becomes Project state or Project instructions/memory.
  - Library becomes Files.
  - Saved becomes Notes or Sources depending on object type.
  - Guide becomes Instructions.
- Update UI copy, menu copy, prompt construction labels, tests, and parity docs.
- Rename "Project Selected" to "This project" or the actual project name.

Acceptance criteria:
- No main surface uses Context/Sources/Library/Files/Saved/Guide as six parallel concepts.
- Prompt construction still sends the same data after label changes.
- User-facing tests/snapshots cover the new labels.

### Packet T - Accessibility, Color, And Typography Discipline

Priority: P2

Why:
The app is close to polished, but small grey metadata, overloaded brand blue, and inconsistent heading weights make important states harder to parse.

Build:
- Reserve brand blue for primary actions and navigation.
- Add a separate verified accent for attestation and trust.
- Increase contrast on:
  - project metadata
  - tab active states
  - helper text
  - menu subtitles
- Add a stronger typography ladder for home sections, sheet headings, and compact panels.
- Run Dynamic Type checks for:
  - home project rows
  - composer
  - model picker
  - project context
  - account sheet
  - share sheet
- Standardize sheet hierarchy: drag handle, Done, centered title, optional top-right action.

Acceptance criteria:
- Metadata text meets WCAG AA at displayed sizes.
- Attestation does not look like a generic selected/active state.
- Common Dynamic Type sizes do not truncate button labels or overlap controls.

## Recommended Sequencing

### Sprint 0 - Trust, Measurement, And Hygiene

1. Packet -1: privacy-preserving telemetry decision, docs, schema, and user-visible setting.
2. Packet O first slice: tests for fixed P1s, setup storage seam, source/focus seam.
3. Packet P first slice: performance signposts and stream-interruption semantics.
4. Packet 0 first slice: attestation status model and verified color token.
5. Packet 0b first slice: shield explainer copy.
6. Packet T baseline: contrast/Dynamic Type audit only, before visual churn.

### Sprint 1 - Parity And Trust Foundation

1. Packet Q: home information diet and progressive disclosure.
2. Packet B: onboarding persistence/account scoping, setup prefill, and auth entry reorder.
3. Packet F: empty-state prompt chips and first actions.
4. Packet A first slice: single-axis Focus model, attachment shelf, and composer hierarchy.
5. Packet R first slice: group chat overflow/action menus and confirm destructive actions.
6. Packet 0 second slice: header attestation indicator and first message shield.
7. Packet C first slice: model picker copy cleanup.

### Sprint 2 - Model/Project Clarity

1. Packet C: model picker tabs and copy cleanup.
2. Packet D first slice: project icon/color and metadata cleanup.
3. Packet S: naming consolidation across UI, prompts, tests, and docs.
4. Packet G first slice: public-link confirmation, share preview copy, expiry, and invite-first path.
5. Packet E first slice: undo toast for archive/move/share revocation.
6. Packet L first slice: Council disagreement panel.
7. Packet M first slice: App Intents for verified chat and selected text.

### Sprint 3 - Category Ownership

1. Packet 0c: signed transcript export plus open verifier fixtures.
2. Packet D second slice: per-project default Focus/tools.
3. Packet H: settings hygiene.
4. Packet I plus Packet T: visual system, accessibility, color, typography, and sheet hierarchy.
5. Packet R second slice: undo coverage for remaining reversible actions.

### Later

1. Packet N: Mac path after iOS quality.
2. Packet J: voice.
3. Packet K: global memory.
4. Packet M widgets/Live Activities/Watch glance.
5. File/canvas/live preview improvements.

## Engineering Notes

- Telemetry must be decided before Sprint 1 user-facing changes. The chosen path is local differential-privacy counters with on-device aggregation, no content telemetry, and a user-visible control.
- Extract setup logic before expanding onboarding. `UserSetupView` and `ChatStore.applySetupProfile` currently share responsibility; a pure `AppSetupPlan` will make tests easier.
- Source/focus behavior needs tests before UI changes. The same mode affects prompt instructions, project attachments, saved links, app web grounding, NEAR Cloud behavior, and IronClaw Mobile behavior.
- Attestation status should be model-aware and route-aware. Avoid showing verified state on NEAR Cloud, IronClaw hosted, or any route not covered by the attestation payload.
- Attestation education copy must avoid overclaiming. It verifies route/model evidence, not answer truthfulness.
- Signed exports need a public verifier, otherwise "verified export" remains app-local trust theater.
- Undo infrastructure should be generic enough for archive, share revocation, project moves, and file deletion.
- Do not bury raw attestation JSON; move it behind expert disclosure, but keep it copyable.
- Performance budgets should be tracked before the visual system pass, because SwiftUI changes on very large view files can hide regressions.
- Stream recovery and multi-device conflict semantics should be product decisions, not accidental behavior.
- The iOS design pass should reduce first-screen concepts before adding new surfaces. Mac planning should wait until the cleaned iOS taxonomy and attestation system are stable.
- Overflow/action menu grouping should be implemented once and reused, so chat overflow and long-press action menus do not drift apart.

## Definition Of Done For The Roadmap

The roadmap is successful when:

- The product has a documented telemetry stance that does not contradict the privacy promise.
- A new user can sign in, choose a goal, see what changed, and start a first useful prompt without understanding internal route names.
- The composer has one clear source/focus axis and one clear trailing action control.
- The model picker helps a user choose, rather than exposing backend/model plumbing.
- Attestation is visible as a continuous trust signal on chat, model, export, and share surfaces.
- Users can understand attestation through a plain-language explainer before seeing raw JSON.
- A third party can verify a signed transcript without the iOS app and without uploading transcript content.
- Council runs can produce a disagreement artifact, not only a synthesis.
- Mobile streams survive interruption or clearly recover by fetching server truth.
- iOS system entry points are intentionally supported or explicitly deferred, and Mac is tracked as a later post-iOS path.
- Consumer settings are clean, while developer diagnostics remain accessible.
- NEAR's field-leading privacy/verifiability story is visible before a user has to open a sheet.
