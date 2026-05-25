# NEAR Private Chat iOS Product Punchlist

Date: 2026-05-25
Revision: v2, reconsidered after the Deep Research Pass

Purpose: concrete design and functionality punchlist to use as the next Claude/Codex implementation spec. This revision keeps the strong parts of the first punchlist, but corrects the places where the research pass exposed bad absolutism: do not remove every explicit compose affordance, do not turn filters into carousel tiles, do not force users to build a Council by hand, and do not ship the visual pass without accessibility, haptics, draft persistence, and search.

Product line:

- Make iPhone excellent first.
- Mac can be a later power-user surface after iPhone quality is stable.
- Do not start iPad work in this phase. Where the research pass validates iPad split view, treat it as future wide-screen/Mac direction unless the product priority changes.

Design stance:

- Keep SF Pro.
- Ignore the full NEAR brand guideline system as a rulebook.
- Use NEAR/Sky iconography and gradient ideas only where they improve hierarchy.
- Brand blue should mostly mean primary action.
- Verifiability needs its own visual language, not generic blue UI.
- Liquid Glass / iOS 26-style glass and spring motion are useful references, but respect Reduce Motion and legibility first.

## What Changed After Reconsideration

- Keep an explicit compose affordance. On home, the `Ask` card can be primary. Inside a thread or non-home surface, keep a top-right compose/pencil icon so users can start a new chat without losing context.
- Replace the proposed 64 x 64 `All / Shared / Archived` tiles with a segmented control or compact filter strip. These are filters, not rich destinations.
- Add a visible recents/resume row for returning users and search across chats, projects, and sources.
- Keep the Agent/Project demotion under the hero, but show only meaningful non-default status, not decorative status pills.
- Make Council one-tap by default: Auto-Council first, builder behind `Customize`.
- Make the attestation layer more central: persistent header shield, per-message shields, Signed Snippet, Live Activity later, and reproducibility/diff workflows after core.
- Add missed reliability basics: draft persistence, paste-to-attachment conversion, haptics, VoiceOver, Dynamic Type, and dark-mode palette.

## Highest-Leverage Moves

These are the moves that matter most by effort-adjusted product leverage:

1. Persistent attestation shield plus per-message attestation state.
2. Signed Snippet with one-line verifier URL.
3. Council thinking tray with per-model TTFT and `Stop waiting`.
4. In-thread agent progress card with pause and inline approval gates.
5. App Intents for `Start verified chat`, `Ask about selected text`, and `Open shared link`.
6. Lock Screen Live Activity with attestation freshness.
7. Auto-Council default with optional `Customize`.
8. Search across chats, projects, and sources.
9. Source freshness indicators.
10. Slash commands in composer.
11. Reproducibility test and Attestation Diff.
12. Route readiness gate from the functionality audit.

## Build Now: Product-Quality iPhone

- Home productization.
- Composer and new-chat empty state.
- Route readiness gate.
- Search, recents, and draft persistence.
- Visual/accessibility tokens.
- Model picker and Auto-Council.
- Project Context taxonomy and source freshness.
- Chat header, titles, breadcrumbs, source expansion.
- Security proof actions.

## Build After Core Is Stable

- Council answer component and raw transcript view.
- Agent templates, context binding, in-thread progress, pause, approvals.
- Branch view for regenerate.
- Signed Snippet, Quick Council, Attestation Diff.
- App Intents, Live Activity, widgets, app icon variants.
- Future Mac/wide-screen proof panel.

## Packet P0 - Home Productization

Goal: make home feel like a confident chat workspace with one primary start path, quick resume, and clear project navigation.

Build:

- Home primary action remains the hero `Ask` card.
- Do not remove compose globally. Keep a top-right compose/pencil icon when the user is not on home. On home, `Ask` is enough.
- Remove `Agent: ready` from the hero top-right.
- In the hero, keep `Ask` full-width.
- Move Agent and Project out of the hero as two small text buttons below it:
  - `Open Agent ->`
  - `New Project ->`
- Replace status chip backgrounds under Ask with one small-caps metadata line:
  - `Verified / Web on / 1 link`
- Only show that metadata line when it says something non-default or useful. Do not decorate the happy path with noise.
- Delete the bottom account footer card. Move avatar/settings to the top-right toolbar.
- Add a search bar in the home header or immediately below it:
  - `Search chats, projects, and sources`
- Add a visible Resume/Recents row for the last three active chats:
  - title, project/context, last updated.
  - include a clear `Resume` affordance.
- Replace the proposed 64 x 64 system tiles with a filter strip or segmented control:
  - `All`
  - `Shared`
  - `Archived`
  - show count badge where useful, especially Shared.
- Keep `Projects` as a real section with `+ New` right-aligned in the header.
- Project row layout:
  - 32 pt project color/icon tile.
  - Semibold project name.
  - One stat line, e.g. `29 chats / 1 link`.
  - No zero-count noise.
  - No `instructions` text unless it is the primary content of the row.
- Add `Today / Yesterday / Earlier` grouping for recents/chat list.
- Long-press project row opens a context menu:
  - `Open`
  - `Rename`
  - `Color & Icon`
  - `Archive`

Data/model needs:

- Persist project color and icon.
- Provide 8 color swatches and around 30 searchable SF Symbol choices.
- Add `Use AI to pick` for icon/color as a delightful optional shortcut.
- Existing project migration should assign stable default icon/color without changing names.

Acceptance:

- Home has one dominant primary action, one explicit resume path, and search.
- `All / Shared / Archived` read as filters, not destinations.
- Projects are visually distinguishable from system filters.
- Account identity no longer consumes bottom screen real estate.

## Packet P1 - Composer And New Chat Empty State

Goal: make the first message obvious, make focus modes understandable, and make send/stop/attachment states feel modern and resilient.

Build:

- Replace the centered logo/text block with:
  - 40 pt brand mark.
  - `What do you want to ask?` in 22 pt semibold.
- Replace generic prompt chips with concrete invitations. Prefer project guide/goal-driven suggestions; otherwise use curated defaults:
  - `Summarize the launch brief in 5 bullets`
  - `Compare Anthropic and OpenAI for this task`
  - `Draft a launch-risk memo from project files`
- Tapping a suggestion fills the composer. It does not send.
- Remove the terminal icon button from the new-chat header. Put `Open Agent` inside overflow.
- Add a chevron to the model/Council chip so it reads tappable.
- Tapping the model chip opens model selection for the next message without leaving chat.
- Focus row treatment:
  - Selected chip is filled.
  - Unselected chips are outlined.
  - `Auto` may use a sparkle glyph and Sky accent, but state must not rely on hue alone.
- Placeholder text changes by focus:
  - Auto: `Ask anything`
  - Web: `Ask with live web`
  - Files: `Ask your project files`
  - Links: `Ask your saved links`
  - Research: `Ask for a researched answer with citations`
- Send button:
  - 32 pt filled blue circle.
  - White arrow.
  - Spring scale from 0.9 when input becomes non-empty.
  - Respect Reduce Motion with cross-fade/no scale.
- While streaming:
  - same control becomes red with stop-square icon.
  - define the mid-stream typing behavior explicitly. Either lock composer until stream completes or allow composing the next draft in a visually separate draft area.
- Pending attachments show in a 56 pt shelf above input:
  - thumbnail/file icon.
  - filename.
  - remove `x`.
- Add paste-to-attachment conversion for long paste over 5,000 characters. The code already has large-paste staging; expose it clearly in the shelf.
- Add slash commands:
  - `/council`
  - `/agent`
  - `/verify`
  - `/project`
  - `/sources`
- Persist unsent drafts across background/foreground and app relaunch, scoped per selected conversation/project.
- Add haptics:
  - chip select.
  - send.
  - model switch.
  - attestation state change.
- Council running tray:
  - model name.
  - queued/thinking/done/failed.
  - TTFT counter once request starts.
  - `Stop waiting` to synthesize from completed models.
  - per-model cancel when one model is slow.
  - use skeleton/progress motion rather than busy bouncing dots.

Acceptance:

- Empty state helps create the first message.
- Composer state survives common mobile interruptions.
- Focus modes teach themselves through placeholder and visual state.
- Council wait time feels controlled rather than mysterious.

## Packet P2 - Model Picker And Auto-Council

Goal: reduce model-picker noise, keep private/verified positioning visible, and make Council one-tap by default.

Build:

- Move `Models | Council` segmented control directly under the `Model` title.
- Top current-model row shows only:
  - provider, e.g. `NEAR Private`.
  - plan/cost, e.g. `Starter`, `Included`, or `Bring key`.
- Move upgrade copy to one bottom strip:
  - `Unlock 29 more models / Upgrade`
- Search placeholder:
  - `Search 33 models`
- Add favorites/pins:
  - pinned models stay at top.
  - recent models appear beneath pins.
- Add filter rows:
  - Row 1: `Private` default-on for privacy-seeking users, `Open weights`, `Reasoning`.
  - Row 2: `Vision`, `Long context`, `Code`, `Reasoning` where model metadata supports it.
- Each model row gets:
  - provider/name.
  - relative-cost chip: `Free`, `Included`, `Higher cost`, `Bring key`.
  - `Verified` check if covered by current attestation.
  - `last verified` timestamp when available, e.g. `attested 2h ago`.
- Tapping a Verified check opens Security to that model.
- Council tab:
  - default is `Auto-Council`.
  - show short explanation: `Picks a private lineup for comparison and synthesis`.
  - `Customize` opens the builder.
- Council builder:
  - selected models list with large reorder handles.
  - add/remove models.
  - synthesizer picker.
  - keep drag targets at least 44 pt.

Acceptance:

- Most users can use Council without assembling models.
- Power users can customize lineup and synthesizer.
- Verification status and cost are visible without over-tagging.

## Packet P3 - Project Context Productization

Goal: make projects read like a useful knowledge workspace with fewer tabs, source freshness, and immediate actions.

Build:

- Use three tabs on iPhone, not four.
- Recommended tab set:
  - `Sources`
  - `Instructions`
  - `Notes`
- Treat files and links as source types inside `Sources`.
- If four tabs survive implementation, prove they fit at Dynamic Type sizes before shipping.
- Delete the `Private File Library / Refresh Library` explainer card. Use pull-to-refresh.
- `Sources` header shows count, refresh icon, and `+`.
- Move `Source title / URL / Add` above the source list or hide behind `+ Add`.
- Source rows use one trailing `...` overflow:
  - Open.
  - Copy.
  - Re-sync.
  - Delete, behind confirmation.
- Add source freshness:
  - `synced 4h ago`
  - `stale / re-sync`
  - `never synced`
- Add `What this project knows` preview:
  - two-sentence system-generated summary.
  - refresh/regenerate when sources change.
- Project hero:
  - roughly 120-140 pt.
  - project icon + name.
  - one useful line, e.g. `Uses your sources and instructions in chat and agents`.
  - small metadata line, e.g. `3 files / 1 link / 3 notes`.
  - no decorative chips.
- Remove `Guided`/`Instructions on` pill. Show instructions inline if present; hide if not.
- File-type icons:
  - tint by type.
  - also show extension badge so color is not the only signal.
- Empty Sources state:
  - `Drop a file here, paste a link, or tap +`
  - visible `+` in header.

Acceptance:

- Project nouns map to user mental model.
- The user can tell what the project knows and whether sources are fresh.
- Empty state has a direct action.

## Packet P4 - Chat Header, Titles, Sources, And Branches

Goal: make the thread named, verified, navigable, and transparent per turn.

Build:

- Persistent attestation shield directly beside the model chip:
  - fresh: Sky dot or subtle filled shield, under 2 minutes.
  - recent: Blue/trust filled, under 1 hour.
  - stale: grey outline.
  - verifying: subtle pulse/spinner.
  - mismatch/failure: system orange or red depending severity.
  - tap opens Security.
- Add per-message attestation chip on assistant messages:
  - shows turn-level verified/stale/unverified route.
  - prevents one fallback turn from poisoning or falsely validating the whole chat.
- Cap title to two lines with ellipsis.
- Long-press title menu:
  - full prompt/title.
  - `Rename chat`.
  - `Generate title`.
- Auto-generate chat title after first assistant response:
  - 3-6 words.
  - replace prompt-as-title default.
- Subtitle becomes breadcrumb:
  - `Private research > IronClaw Phone QA`
  - tap project name opens Project Context.
- Source chip:
  - render only when sources were actually consulted.
  - label with count, e.g. `3 sources`.
  - tap expands inline into source list.
  - if per-claim citation data is reliable, show which paragraphs used each source; otherwise show only consulted sources.
- Regenerate should preserve previous answer as sibling branch:
  - message-level chevron to switch variants.
  - future wide-screen/Mac can show branch tree.
- Long-press any message shows timestamp.

Acceptance:

- Chat never looks like a debug log after first response.
- Verification is visible per route and per turn.
- Source labels are trustworthy because they only appear when source paths actually ran.

## Packet P5 - Council Answer As A Component

Goal: make Council outputs inspectable, not just summarized prose.

Build:

- Render Council synthesis as a structured component, not raw Markdown.
- Sections:
  - `Direct answer`
  - `What the council agrees on`
  - `Disagreements or uncertainty`
  - `Recommended next step`
- Only show sections that have content. Do not show empty theatre.
- Each section has small-caps label and chevron collapse.
- Header strip above answer:
  - one pill per Council model.
  - `Synthesis` pill.
  - active pill filled, inactive outlined.
  - tapping a model pill shows raw answer.
  - tapping `Synthesis` returns to combined answer.
- Add side-by-side/raw transcript view:
  - iPhone can use horizontal paging or bottom sheet.
  - future wide-screen can use columns.
- Add confidence/uncertainty fields when the model output and prompt support it.
- Add `Disagreement` export action:
  - copies disagreement section plus signed attestation reference.
- Add `Ask the dissenters`:
  - only appears when real disagreement was detected.
  - button label should name the disagreement, e.g. `Ask why Qwen disagreed on timeline`.

Acceptance:

- Council no longer looks like ordinary Markdown.
- Raw model answers are one swipe/tap away.
- Dissent workflows appear only when there is meaningful dissent.

## Packet P6 - Agent Surface And In-Thread Progress

Goal: make Agent feel connected to project context, safe to run, and visible inside chat.

Build:

- Replace Agent subtitle:
  - from `Shell + Git + Web`
  - to `Give it a task. It uses your project's context.`
- Convert `Coding`, `Local Test`, and `GitHub` into starter templates.
  - tapping `Coding` prefills `Plan a feature: ...` and places cursor at placeholder.
- Promote `Auto skills` into top-row control:
  - `Skills: Auto v`
- When launched inside a project, auto-bind that project.
- Replace `No project selected` with:
  - `Using IronClaw Phone QA > 1 link / 3 notes`
  - `Change`
- Add in-thread agent progress card:
  - sticky current-step banner.
  - last three steps inline.
  - `+N more` collapsible history.
  - success/failure/retry states.
- Add pause/resume for long agent runs.
- Add inline approval gates for destructive or expensive actions:
  - write file.
  - run external command.
  - call external API.
  - spend paid credits.
- Approval cards should be in-thread with context, not generic modal alerts.

Acceptance:

- Agent starter pills do something.
- Project context is automatic when launched from a project.
- Long agent runs are inspectable, pausable, and approval-safe.

## Packet P7 - Security And Attestation Actions

Goal: move attestation from a report display to a proof workflow.

Build:

- Add top-row `Verify on-device` CTA:
  - runs local verifier.
  - shows pass/fail quickly when data is available.
- Add `Share proof`:
  - exports attestation JSON only.
  - no transcript.
- Add `View on verifier.near.ai`:
  - show QR code.
  - public verifier opens with this proof/transcript reference preloaded where possible.
- Replace `Model attestations: 1` copy with readable facts:
  - `Verified / GLM 5.1-FP8 / Intel TDX`
  - each fact tappable for detail where possible.
- Add hardware identity display for technical users:
  - TEE type.
  - GPU model.
  - firmware/runtime version where available.
- Add per-message reproducibility test:
  - rerun same prompt on same model.
  - compare attestation and output diff.
  - frame as `model behavior changed since last session` rather than scary "drift" by default.
- Add collapsed `Why this matters` under 60 words:
  - "TEE proof shows the model route produced this answer inside a verified runtime. It does not prove the answer is true; it proves where it came from."

Acceptance:

- User can act on proof, not just inspect it.
- The sheet explains trust without overclaiming truth.
- Technical users can inspect hardware/runtime identity.
- Demo can show QR-to-verifier as a credible trust moment.

## Packet P8 - Visual, Motion, Accessibility, And Haptics

Goal: stop overloading blue and make the product feel native, legible, and physically responsive.

Build semantic color tokens:

- `actionPrimary`: Blue.
- `trustVerified`: verified green.
- `trustFresh`: Sky.
- `warn`: system orange.
- `destructive`: system red.
- `surface`: Off-White for light mode.
- `surfaceDark`: dark-mode base.
- `panel`.
- `border`.
- `textPrimary`.
- `textSecondary`.

Rules:

- Refactor literal `.brandBlue` uses to semantic tokens.
- Cap visible Blue per screen at roughly three active elements.
- Replace pure white background with Off-White `#EEEEEB` in light mode only.
- Define a proper dark-mode palette at the same time.
- Standardize corner radii:
  - 14 pt continuous for cards/sheets.
  - 10 pt continuous for buttons.
  - capsule for chips.
- No square buttons in composer or chat header.
- Motion:
  - use iOS/Liquid-Glass-like spring defaults as starting point: response around 0.4, damping around 0.5.
  - test and tune in app; avoid exaggerated bounce.
  - Reduce Motion falls back to cross-fade/no scale.
- Apply motion to:
  - chip selection.
  - tab switch.
  - sheet present/dismiss.
  - send-button activation.
  - attestation state change.
- Haptics:
  - focus chip select.
  - send.
  - model switch.
  - successful verify.
  - verification failure.
- Accessibility:
  - VoiceOver labels for model chip, attestation states, source chips, and send/stop.
  - Dynamic Type through xxxLarge.
  - 44 pt minimum interactive targets.
  - no state communicated by color alone.
- Hero gradient candidate:
  - `#0091FD -> #83DCFF`.
  - at most one hero gradient per screen.
  - optional visual test, not a brand requirement.

Acceptance:

- Blue no longer means action, trust, selection, and decoration at the same time.
- Dynamic Type and VoiceOver work on the main flows.
- Motion feels modern but disables cleanly.
- Haptics make key interactions feel intentional.

## Packet P9 - First-Run Mode And Welcome Project

Goal: make onboarding functional after setup, not just pretty.

Build:

- Add visible Beginner/Power choice during onboarding.
- Do not hide paid/advanced features silently.
- Beginner mode hides Agent, Council, NEAR Cloud, and Developer disclosure until:
  - user explicitly switches to Power, or
  - product decides to show a clear prompt after early usage.
- Conversation 4 can show `Try Council`, but do not block users who deliberately chose Power mode.
- Add curated Welcome project for new accounts:
  - sample file, e.g. privacy whitepaper PDF.
  - sample link, e.g. near.ai/blog.
  - instruction: `Be concise. Cite sources.`
  - example chat showing Council and attestation.
- Setup completion routes into:
  - first chat.
  - research brief.
  - project workspace.
  - agent readiness.
- Setup should check route readiness before promising Agent/Council/Cloud paths.

Acceptance:

- A new user has useful content without creating anything.
- Advanced features exist but do not crowd first use.
- Users who want power mode can opt in immediately.

## Packet P10 - Platform Enhancements After iPhone Core

Goal: use OS surfaces to make verifiability ambient, after the core product is stable.

Build later:

- App icon variants:
  - Sky icon.
  - Black icon.
- Lock Screen Live Activity:
  - `Verified / last attested 2m ago`.
  - shield glyph.
- App Intents:
  - `Start a verified chat`.
  - `Ask NEAR Private about <selected text>`.
  - `Open shared link in NEAR`.
- Widgets:
  - small: pinned project + attestation freshness.
  - medium: three recent chats.
- Future Mac/wide-screen:
  - chat plus pinned Security/Attestation proof panel.

Acceptance:

- These ship only after route readiness, onboarding utility, composer, home, and attestation basics are stable.

## Packet P11 - Category Features

Goal: build things competitors cannot easily copy.

Build after core:

- Quick Council:
  - long-press or swipe action on any assistant message.
  - `Compare with Council`.
  - sends same prompt to Council and stacks result below original.
- Signed Snippet:
  - long-press any sentence.
  - `Copy with proof`.
  - pasted format is short and public-verifier friendly:
    - `GLM 5.1-FP8 via NEAR / verify: https://near.ai/v/abc123`
  - verifier URL must work without login.
- Attestation Diff:
  - if same prompt on same model yields a meaningfully different answer, show:
    - `Model behavior changed since last session`
  - one-tap diff view.
- Signed transcript publish:
  - publish full chat as a public verifier page with attestation chain.
  - works like a shareable gist/Carrd for legal, finance, medical, and audit use cases.

Acceptance:

- Attestation becomes a workflow layer, not just a report.
- Council becomes an upgrade path inside ordinary chat.
- Verified answers can travel outside the app.

## Best Next Build Order

1. Packet P8 - Visual, motion, accessibility, and haptics.
2. Packet F1 from functionality audit - Route readiness gate.
3. Packet P0 - Home productization.
4. Packet P1 - Composer and new-chat empty state.
5. Packet P2 - Model picker and Auto-Council.
6. Packet P3 - Project Context productization.
7. Packet P4 - Chat header, titles, sources, and branches.
8. Packet P7 - Security and attestation actions.
9. Packet P9 - First-run mode and Welcome project.
10. Packet P6 - Agent surface and in-thread progress.
11. Packet P5 - Council answer component.
12. Packet P10/P11 - Platform and category features.

If only one Claude/Codex sprint is available, do:

- route readiness gate.
- P8 tokens/accessibility/haptics baseline.
- P0 home with search/recents/filter strip.
- P1 composer with attachment shelf, draft persistence, focus placeholders, and send/stop.

## Suggested Claude/Codex Prompt

> Work in `/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS`. Implement the first iPhone product-quality sprint from `review-artifacts/NEARPrivateChatIOS-product-punchlist-2026-05-25.md`: route readiness gate from the functionality audit, Packet P8 visual/accessibility/haptics baseline, Packet P0 home productization, and Packet P1 composer/new-chat improvements. Reconsideration note: do not remove compose globally; keep a top-right compose/pencil icon off-home. Do not create 64 x 64 tiles for All/Shared/Archived; use segmented control or compact filter strip. Add home search across chats/projects/sources, last-three recents/resume row, project icon/color persistence, focus-aware placeholders, visible attachment shelf, draft persistence, long-paste attachment affordance, and filled circular send/stop state. Keep SF Pro, ignore full NEAR brand guidelines, and do not start iPad work. Add focused tests for new persistence/state helpers and run the iOS test target if available.

