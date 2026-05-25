# NEAR Private Chat iOS — Elite Design Audit v2 Upgrade

Date: 2026-05-25
Status: Supplements `NEARPrivateChatIOS-elite-design-product-audit-2026-05-25.md`. Does not replace it.
Execution brief: use `NEARPrivateChatIOS-next-design-pass-brief-2026-05-25.md` for the next implementation/design pass. That brief resynthesizes this memo into priority order and deliberately defers platform-moat work like Live Activities until P0 visual/product-truth issues are fixed.
Live-app correction: `NEARPrivateChatIOS-live-app-review-next-pass-2026-05-25.md` and `review-artifacts/live-app-review-2026-05-25/` supersede the screenshot-only assumptions in this memo. Treat this v2 upgrade as strategic background, not the controlling current-state review.
Inputs: existing audit doc, latest-smoke screenshots, latest-screenshot-index, deep web research (May 2026 cutoff) across ChatGPT, Claude, Perplexity, Gemini, Copilot, Grok, Le Chat, Poe, DeepSeek, Linear, Things 3, Notion, Cash App, Stripe, Signal, 1Password, Apple Wallet, iOS 26 / Liquid Glass HIG, Codex Mobile, Claude Code Mobile, Gemini Spark, NN/g, Smashing, Honeycomb, plus accessibility guidance from Apple HIG / Codakuma / Use Your Loaf.

## Why a v2

The existing audit's framing is right. Three things changed after the research pass:

1. **Several rules in the audit are too forgiving.** The "3 visible blues per screen" cap is more lenient than what shipping best-in-class apps actually hold to. Truth is closer to **one saturated brand color per scene**.
2. **The proof state model is wrong in subtle ways.** "Fetched" is being conflated with "verified" in language and color. These are independent state machines and must read differently to users.
3. **The IA question doesn't go far enough.** Asking "should Council/Proof be top-level?" is the wrong question. The right answer is: top-level on iPhone caps at 3-4 destinations per Apple HIG and shipping precedent. Council, Proof, Shared, and Agent are *modes / states / sheets*, not destinations.

Plus the audit missed iOS 26-native superpowers (Live Activities + `BGContinuedProcessingTask`) that, if claimed early, become moats no peer ships on iOS today.

This document is the deltas to apply on top of the existing audit.

## Latest screenshot reality check

This section is historical. A later live-app run captured the actual current app under `review-artifacts/live-app-review-2026-05-25/`. Use that pack and `NEARPrivateChatIOS-live-app-review-next-pass-2026-05-25.md` first. The live review confirms the app is materially improved on Home, Composer, Model Picker, More Menu, and Project Context, while exposing new P0 state-truth bugs around setup readiness, Cloud selection, Hosted IronClaw copy, and proof-chip truncation.

The newest captures in `latest-smoke/` show only the Setup screen across four points in time:

- `iphone17pro-current.png` (07:21) — original "Make it yours" setup with Skip/Setup/Finish header + the dense survey below.
- `iphone17pro-2026-05-25-setup-polish-booted.png` (07:43) — new "Start with one job" hero, single "Setup" title, CTA "Ask a private question". Cleaner.
- `iphone17pro-2026-05-25-post-four-docs.png` (07:37) — same screen, but CTA reads "Start an LLM Council question" while Private Chat is selected. **The CTA/selection mismatch bug is reproduced in screenshot evidence.**
- `iphone17pro-2026-05-25-after-setup-card-font-fix.png` (08:49) — post-font-fix, same hero, "Ask a private question" CTA. The "Ready on day one" preview card is below fold and not captured.

**Implication.** The 2026-05-24 captures are no longer enough for current-state judgment. Keep the strategic recommendations, but validate every screen-specific critique against the live-app pack before implementing.

---

# What the existing audit got right (do not redo)

- The intensity-ladder framing (Level 0 → Level 5) is the single most valuable architectural insight in the audit. Keep and ship.
- "Three products" diagnosis (Private Chat + Council + Agent + Context + Cloud + Attestation) is accurate.
- Vocabulary taxonomy (Chat / Project / Sources / Instructions / Notes / Proof / Agent / Council) is the right *language*.
- Proof-result-first instead of diagnostics-first in Security is correct.
- Council and Agent as contextual upgrades, not competing top-level products, is the right framing.
- Onboarding-as-launchpad-not-survey is correct in spirit.
- Project hero shouldn't reuse the Home command-card gradient.
- 154 direct `brandBlue` references must be replaced by semantic tokens.
- The seven research questions are the right questions.

# What the existing audit got wrong or oversimplified

## 1. The "3 blues per screen" rule is too lenient

**Evidence.** Stripe Dashboard uses one saturated accent (`#635BFF`) for the single primary interactive control per scene; the rest is monochrome. Cash App went further and used green deliberately to avoid blue-overload in fintech. Apple's iOS 26 Liquid Glass docs explicitly: *"Apply Liquid Glass sparingly, on key surfaces such as important controls or navigation bars"* and *"choose one primary hue and one or two complementary accents."*

**Correction.** Replace the audit's "cap at 3 visible blues per screen" with **one saturated brand-blue per scene**, reserved for the single primary CTA. Inactive system blue (links, system selection chrome) doesn't count as a brand statement. Audit Home, Setup, Composer, Model Picker, Project, Security, Agent, Council against the stricter rule.

## 2. "Fetched" ≠ "verified" — the audit treats them as adjacent labels

**Evidence.** Signal's own published research on Safety Numbers shows users don't map crypto primitives to "is this private?" GitHub's "Verified" badge has years of community confusion threads where users can't act on the "unverified" state. Apple Wallet's `Verify with Wallet` API uses **three-part UI** (request → Accept/Decline → issuer-signed identity claim) — never "we received metadata" written as "Verified."

**Correction.** Define five proof states as a single state machine: `none | fetched | verified | stale | mismatch`. Never use the word "Verified" unless the state machine is in `verified` (signature checked against known measurement / IACA / signer set). Build one `ProofCapsule` SwiftUI component, five visual states, distinct glyph + color + microcopy per state. This is the most important UX-truth fix in the entire app — it deserves a P0 with an explicit state-machine specification.

## 3. The IA question doesn't go far enough

**Evidence.** Apple HIG on Tab Bars: *"In general, use three to five tabs… use the minimum number of tabs required."* ChatGPT iOS, Claude iOS, Le Chat, Grok all converge on three or four. Notion's March 2026 redesign added a four-tab sidebar (Pages / Chats / Meetings / Notifications) *because Notion has four genuinely separate workspaces*. NEAR Private Chat does not — Council and Agent are upgrades to a chat, not separate inboxes.

**Correction.** Make the architectural claim explicitly: **top-level caps at 3 tabs (Chats / Projects / Settings)**. If Agent must be top-level for product reasons, four; never five. Council, Proof, Shared, and Search are *modes / states / sheets / filters*, not destinations.

## 4. Onboarding redesign is still too long

**Evidence.** NN/g's generative-AI onboarding research is explicit: first-time users need *brief, in-context examples*, not preference setup. Linear's "anti-onboarding" model pre-populates a workspace with ideal demo data and zero walkthrough. ChatGPT iOS, Claude iOS, and Le Chat all ship a ~3-step minimum (sign-in, light permission, working chat).

**Correction.** The audit proposes 3 screens. The right shape is **one screen, one question, one go**: a goal textarea with placeholder "What should NEAR help with first?", three example chips that prefill the textarea, one quiet "Use the web?" toggle (default off / private), one primary CTA derived from selection state. Tap CTA → routed to chat with goal prefilled and Send armed. Beginner/Power, default model, Council preferences, Agent tools all go to a Settings shelf that surfaces only after observed behavior triggers it.

## 5. CTA/selection mismatch is an architecture problem, not a copy problem

**Evidence.** The captured screenshot evidence (`post-four-docs.png`) shows Private Chat selected and the CTA reading "Start an LLM Council question." This is a state-derivation bug — the radio state and the CTA label come from independent state sources. Best-practice prevention is **single source of truth + assertive snapshot tests** (Stripe and Linear gate this on PRs).

**Correction.** Fix at the state layer: the CTA label must be a `@Binding`-derived computed value of the same enum the selection is bound to. Add a snapshot-test matrix (4 modes × 2 web states × 2 length states) gated as a CI smoke. This is not a design-review fix; it is an engineering-architecture fix that prevents the bug from regressing.

## 6. The audit does not name iOS 26 Liquid Glass as a force

**Evidence.** Liquid Glass changes corner radii via `containerConcentric`, handles its own depth via lensing and specular highlight, and does selection signaling natively. Apple's docs explicitly: *"Apply Liquid Glass sparingly"* + *"do not stack additional drop shadows on glass surfaces."*

**Correction.** The component system must be built *on top of* Liquid Glass, not against it. Stop hand-tuning shadows on glass surfaces. Adopt `.containerConcentric` corner radii. Use the system material for selection state where possible; the OS does the work now.

## 7. Agent run is underweighted as a differentiation surface

**Evidence.** May 2026 is the most contested frontier on long-running agent UX: ChatGPT Codex Mobile rolled out May 14, Claude Code Mobile is in research preview, Gemini Spark + Daily Brief, GitHub Mobile Live Notifications for coding agent progress (Feb 2026). iOS 26 shipped `BGContinuedProcessingTask` + Live Activities — the platform-native primitive for long-running task UI.

**Correction.** The audit's "expand the status strip into a timeline card" is correct but understates the opportunity. The right move is: **Agent Run Card in thread + iOS 26 Live Activity on Lock Screen**. Sticky current step at top, last 3 completed steps beneath, inline risk-tiered approvals, Pause/Resume/Stop in card overflow, run-end five-section summary. Lock Screen activity shows current step + Stop button. This is a platform-native superpower no peer ships on iOS today.

---

# What the audit missed entirely

1. **iOS 26 Live Activities + `BGContinuedProcessingTask` for Agent runs.** Apple shipped the right primitive in iOS 26 specifically for this. Not using it cedes the differentiator.

2. **Disagreement detection at claim level (not prose level).** Without this, the audit's correct prohibition on empty Disagreement sections cannot be implemented — the section will either always be there or always be missing.

3. **Single-source-of-truth principle for CTA derivation.** The shipped CTA mismatch bug is an architecture problem; fix it once at the state layer with snapshot tests, not in design review.

4. **Two-sentence consumer TEE copy ready to ship.** Without a canonical version, every internal team rewrites attestation copy and inconsistency leaks back in. Canonical text:
   > *Your messages are processed inside a secure chip that runs sealed code — the operator of the server cannot read what you send, even if they wanted to. NEAR Private Chat checks this chip's signature before each session, so you can prove that nothing else was running on the machine.*

5. **Haptic mapping discipline.** Audit mentions haptics but does not specify the semantic map. Without a centralized `Haptic` enum, decorative haptics will accrete.

6. **The Project chip on the composer** as the user's primary "what does this answer know?" affordance. Tap the chip → opens the project's Sources tab. This is the legibility lever for Sources / Files / Notes that the audit gestures at but doesn't ship.

7. **Approval risk tiering** (`readonly` / `local-write` / `network` / `destructive`) instead of per-tool. Per-tool approval produces approval fatigue within a single run.

8. **The proof block in share/export artifacts.** Without it, "shared verified answers" carry no credibility outside the app — and the entire trust differentiator collapses at the share boundary.

9. **Trust palette specification outside blue** with hex values, contrast targets, and dark-mode variants. The audit asks the right question but doesn't commit:
   - `proofVerified` ≈ `#15BE53` (4.5:1 on Off-White; dark-mode variant `#34D399`)
   - `proofStale` ≈ `#F5A623` (3:1 large text; dark-mode `#FBBF24`)
   - `proofMismatch` ≈ `#E5484D` (Apple `systemRed`-adjacent)
   - `routeCloud` neutral grey, never blue
   - `routePrivate` lock glyph in `proofVerified`

10. **Snapshot/visual-regression test pack for the eight surfaces.** Without it, the intensity-ladder enforcement will not survive a quarter of feature work.

11. **`ViewThatFits` chip rows across the app.** AX2+ users cannot use horizontal chip rows. Default `HStack`, AX fallback to a `Menu` button. Apply to Composer focus row, Model Picker filter chips, Council model pills, Project Source filter pills.

12. **Council as a designed `CouncilArtifact` view** instead of a `CouncilResponseGroup` wrapper. Single card, five sections: synthesis claim → agreement strip → disagreement (conditional render) → next step → raw answers (collapsed).

13. **The two-question-test for top-level navigation.** Anything that doesn't pass both "is this a destination?" and "would a returning user want to land here?" goes into the modes layer, not the tab bar.

---

# Revised priority stack

## P0 — must land before next visible release

### P0.1 — Proof state machine and ProofCapsule

Define `proof.state ∈ {none, fetched, verifying, verified, stale, mismatch}`. Ship `ProofCapsule` with five visual states (none, fetched, verified, stale, mismatch). Distinct glyph, distinct non-blue color, distinct microcopy per state. Bind to assistant turns. Replace every "Verified" label in the app with a state-derived label. Ship the two-sentence TEE copy verbatim in `Why this matters`.

### P0.2 — One-screen onboarding with state-derived CTA

Collapse to a single Setup screen: goal field + three example chips + "Use the web?" toggle + state-derived CTA. After Start, route to chat with prompt prefilled and Send armed. Snapshot-test matrix gates the CTA-mismatch bug.

### P0.3 — Top-level tab discipline

Cut to three tabs: Chats / Projects / Settings. Shared becomes a filter inside Chats. Council, Proof, Agent become modes/contextual upgrades, not destinations. Search becomes a mode (tap magnifier in nav bar → search takes over the screen).

### P0.4 — One saturated brand-blue per screen

Audit Home, Setup, Composer, Model Picker, Project, Security, Agent, Council. Replace all 154 direct `brandBlue` references with semantic tokens in a single PR. After this pass, the only place `brandBlue` exists is the token file.

## P1 — next design-pass tier

### P1.1 — CouncilArtifact

Convert `CouncilResponseGroup` from a wrapper into a designed artifact. Five sections, synthesis-first, claim-level disagreement detection (never empty-section theatre), `Synthesize now` conditional on idle + ≥2 of N models complete + ≥700-token combined raw length. `Ask the dissenters` prefills the composer with the contested claim named and routes only the dissenting models.

### P1.2 — Agent Run Card + iOS 26 Live Activity

Sticky current step + last 3 completed steps + inline risk-tiered approval card + Pause/Resume/Stop in overflow + run-end five-section summary (Outcome / Files / Tests / External actions / Open risks). Wire `BGContinuedProcessingTask` + Live Activities so runs surface to the Lock Screen with current step + Stop button.

### P1.3 — Trust palette + intensity ladder as real tokens

Ship the hex values + dark-mode variants for `proofVerified` / `proofStale` / `proofMismatch` / `routeCloud` / `routePrivate`. Ship the seven intensity-ladder tokens (`surfaceBase` / `rowPlain` / `panelSoft` / `rowSelected` / `commandPrimary` / `proofArtifact` / `danger`). Build a visual-diff harness that flags any screen with >1 Level-4 element.

### P1.4 — Approval risk tiering

Four tiers (`readonly` / `local-write` / `network` / `destructive`), surfaced in approval-card copy, never per-tool. Per-tool approval banned.

### P1.5 — `ViewThatFits` for every horizontal chip row

Audit Composer focus row, Model Picker filter chips, Council model pills, Project Source filter pills. Default HStack, AX fallback to Menu button. Status capsules switch to `LazyVStack` at AX.

### P1.6 — Share/export proof block

Embed the verified proof artifact in every shared chat and exported PDF/Markdown. Footer block: model, attested platform, proof short-code, freshness, link to verify. Without this, the verifiable-AI differentiator does not survive outside the app.

## P2 — design hygiene that prevents regression

### P2.1 — Centralized `Haptic` enum

Seven semantic cases mapped to events: `send`, `approvalConfirmed`, `proofVerified`, `routeChangedToCloud`, `agentApprovalRequested`, `councilSynthesisReady`, `mismatch`. Ban inline `UIImpactFeedbackGenerator(.x).impactOccurred()` calls in feature code. Respect system Reduce Motion as the default.

### P2.2 — Project chip on the composer

Tap → opens the project's Sources tab. This *is* the user's "what does this answer know?" affordance.

### P2.3 — Snapshot/visual-regression test pack

Eight surfaces × {default, AX-medium, AX-large, Reduce Motion, dark mode} = 40 snapshots gated on every PR. Prevents the intensity-ladder from rotting.

### P2.4 — Fresh full screenshot extraction

Per the gap in `latest-screenshot-index-2026-05-25.md`: capture the full ten-surface set against the current build (setup top + Ready-on-day-one + home + composer + model picker + council + project context + security + agent + share) before the next audit pass.

### P2.5 — Replace command-card gradient discipline

Home keeps the brand command card. Project gets a project-color header. Agent gets a workspace material (tool-orange accent for active runs). Security gets a proof seal in trust colors. Setup uses a lighter onboarding header after the first screen. Do not use the same gradient on four different surfaces.

---

# The 10 highest-leverage moves for the next design pass (ranked)

1. **Split `fetched` from `verified` in state and in UI.** Five distinct states, non-blue trust palette, bound to assistant turns. Ship the two-sentence TEE copy.
2. **One-screen onboarding with state-derived CTA + snapshot tests.** Kills the survey feel and the shipped mismatch bug at the architecture layer.
3. **Cut top-level to 3 tabs.** Chats / Projects / Settings. Council, Proof, Shared, Agent become modes / filters / contextual upgrades.
4. **Council as a designed artifact card** with synthesis-first, claim-level disagreement, conditional sections.
5. **Agent Run Card backed by iOS 26 Live Activity + `BGContinuedProcessingTask`.** Platform-native long-running UX no peer ships on iOS.
6. **One saturated brand-blue per screen.** Replace 154 direct `brandBlue` references with semantic tokens in one PR.
7. **Trust palette + intensity ladder as real SwiftUI tokens.** Hex values, dark-mode variants, contrast targets, visual-diff harness.
8. **Approval risk tiering** (4 tiers, never per-tool) across every approval surface.
9. **`ViewThatFits` chip rows + centralized `Haptic` enum + AX/Reduce-Motion test matrix.** A11y becomes P1, not P2.
10. **Share/export proof block.** Without it, the entire verifiable-AI story dies at the share boundary.

---

# Updated Claude/Codex build prompts

These replace the prompts in §"Build Prompts For Claude/Codex" of the existing audit where they overlap.

### Prompt 1 — Proof state machine + ProofCapsule (P0)

> Define `proof.state` as an explicit Swift enum `{ none, fetched, verifying, verified, stale, mismatch }` and a `ProofCapsule` SwiftUI view that renders all five states with distinct glyph + non-blue color + microcopy. Bind to assistant turns and the chat header. Never display the word "Verified" unless `state == verified` with a real signature check. Use `proofVerified #15BE53` for verified, `proofStale #F5A623` for stale, `proofMismatch #E5484D` for mismatch. Add dark-mode variants. Replace every existing "Verified"/"Attested" label in the app with a state-derived label.

### Prompt 2 — One-screen onboarding with state-derived CTA (P0)

> Collapse setup to a single screen: goal textarea, three example chips that prefill it, a quiet "Use the web?" toggle (default off), one primary CTA. The CTA label must be a `@Binding`-derived computed property of the same enum the selection is bound to — no separate string sources. After Start, route directly to a chat with the prompt prefilled and Send armed. Add a snapshot-test matrix (4 modes × 2 web × 2 length) gated on CI that asserts the verb in the CTA matches the selected mode. Move Beginner/Power, default model, Council prefs, Agent tools to a Settings shelf.

### Prompt 3 — Top-level tab cut (P0)

> Cut top-level navigation to three tabs: Chats / Projects / Settings. Move Shared into Chats as a filter pill (`All / Shared / Resumed`). Replace persistent search with a tap-to-mode magnifier in the nav bar. Council and Proof become modes/sheets, never tabs. Agent is reachable via composer slash command and a contextual "Run as Agent" action; if product still requires Agent as a tab, ship four — never five.

### Prompt 4 — One saturated blue per screen (P0)

> Replace every direct `Color.brandBlue` reference (154 occurrences in `AppShellView.swift` etc) with semantic tokens: `actionPrimary` for the single primary CTA per screen, `proofVerified`/`proofStale`/`proofMismatch` for trust state, `routeCloud`/`routePrivate` for route state, `selectionSubtle` for inactive selection. After the PR, `brandBlue` exists only in the token file. Add a lint that fails the build if `Color.brandBlue` is referenced outside the token file.

### Prompt 5 — CouncilArtifact (P1)

> Convert `CouncilResponseGroup` from a message wrapper into a designed `CouncilArtifact` view. Single card, five vertical sections: (1) synthesis claim large+bold, (2) per-model agreement pill strip, (3) Disagreement (conditional render only when claim-level extraction returns ≥1 contested proposition), (4) next-step suggestion, (5) raw answers as collapsed per-model panels. `Synthesize now` button in artifact header, shown only when user idle ≥1.5s + ≥2 of N models complete + combined length ≥700 tokens. `Ask the dissenters` prefills the composer with the contested claim and routes only the named models.

### Prompt 6 — Agent Run Card + Live Activity (P1)

> Replace the generic Agent status strip with an in-thread `AgentRunCard`: sticky current step at top, last 3 completed steps beneath, inline approval card with risk tier + plain-language explanation, Pause/Resume/Stop in card overflow. On run completion, render a five-section summary: Outcome / Files / Tests / External actions / Open risks. Wire iOS 26 `BGContinuedProcessingTask` + `ActivityKit` so runs >30s surface on Lock Screen with current step + Stop button. Use a tool-orange accent for active runs, not brand blue.

### Prompt 7 — Approval risk tiering (P1)

> Replace per-tool approval prompts with four risk tiers: `readonly` (auto), `local-write` (single approve per run), `network` (per-domain), `destructive` (always re-prompt). Approval card UI surfaces the tier name and a plain-language explanation, never the raw tool name. Persist tier-level grants for the duration of a single run only.

### Prompt 8 — Trust palette + intensity ladder tokens (P1)

> Define `proofVerified`, `proofStale`, `proofMismatch`, `routeCloud`, `routePrivate` colors with hex + dark-mode variants + WCAG contrast targets. Define seven intensity-ladder tokens: `surfaceBase` / `rowPlain` / `panelSoft` / `rowSelected` / `commandPrimary` / `proofArtifact` / `danger`. Build a visual-diff harness that captures every screen and flags any with >1 Level-4 element. Wire to CI.

### Prompt 9 — A11y + Haptic discipline (P1)

> Audit every horizontal chip row in the app and wrap in `ViewThatFits` with an AX fallback to a `Menu` button. Status capsules switch to `LazyVStack` at AX sizes. Add a centralized `Haptic` enum with 7 semantic cases: `send`, `approvalConfirmed`, `proofVerified`, `routeChangedToCloud`, `agentApprovalRequested`, `councilSynthesisReady`, `mismatch`. Ban inline `UIImpactFeedbackGenerator` calls. Respect Reduce Motion as the default. Add a Dynamic-Type × VoiceOver × colorblind × Reduce-Motion test matrix gated on every release.

### Prompt 10 — Share/export proof block (P1)

> Every shared chat and exported PDF/Markdown gets a proof footer block: model, attested platform, proof short-code, freshness, link to verify. The footer is unconditional — even shared chats with no proof artifact show "No proof attached" rather than omitting the block. The verifier link opens to the public verifier page with the transcript pre-loaded.

---

# Definition of done for v2

The next design pass is "done" when:

- A screenshot diff between the app and Cash App / Stripe Dashboard / Linear iOS shows the same restraint posture: one saturated brand color per scene, monochrome elsewhere.
- "Verified" never appears in the UI unless the proof state machine is in `verified`.
- The top tab bar has 3 destinations, 4 if Agent is product-required.
- An automated snapshot test catches the CTA mismatch bug if it tries to regress.
- Long-running Agent runs surface on the Lock Screen via Live Activity.
- Every horizontal chip row collapses gracefully to a Menu at AX sizes.
- Share/export artifacts carry a proof footer block, signed.
- Council renders as a single artifact card with conditional disagreement, never empty sections.
- The CSS-level audit of `brandBlue` references returns zero outside the token file.

If those land, NEAR Private Chat moves from "loaded prototype" to "premium private AI instrument" — which is what the existing audit's bottom line correctly aimed for.

---

# Sources (full set in companion research transcript)

iOS 26 / Liquid Glass HIG, Apple Developer docs (Wallet, BackgroundTasks, ActivityKit, Accessibility, Tab Bars, Color), NN/g, Smashing Magazine (Agentic AI UX, Disabled Buttons), Linear / Things 3 / Notion mobile patterns, Stripe Design Tokens, Cash App Evergreen Design System, Signal Safety Numbers research, Apple Wallet `Verify with Wallet`, GitHub Verified-badge community thread #153997, ChatGPT iOS / Codex Mobile (OpenAI May 14 2026), Claude Code Mobile (Anthropic + Sealos), Gemini Neural Expressive (May 2026, blog.google), Gemini Spark + Daily Brief, Microsoft Copilot Model Council + Critique (March 2026), Poe multi-bot chat, Le Chat iOS (Computerworld), Perplexity Comet for iOS (MacStories, perplexity.ai), Codakuma + Use Your Loaf Dynamic Type, Honeycomb Agent Timeline, GitHub Mobile Live Notifications (Feb 2026), icmd.app Agentic Product Stack 2026.
