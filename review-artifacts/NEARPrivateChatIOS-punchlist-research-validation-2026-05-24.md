# NEAR Private Chat iOS — Punchlist Research Validation

Date: 2026-05-24
Method: deep research pass against ChatGPT, Claude, Perplexity, Gemini, Copilot, Grok, Le Chat, Poe, DeepSeek, Arc Search, Raycast, Things 3, Linear, Notion, Cash App, Stripe, 1Password, Signal, plus iOS 26 HIG, Liquid Glass guidance, Material 3 Expressive motion research, and NEAR AI's own attestation docs.

## What the research validated, refined, killed, or missed

### Home
- **Validated.** Demote bottom account footer, avatar top-right; project rows with color tile + name + one-line stats; Today/Yesterday/Earlier date groups; long-press peek menu; Agent/Project as small text-buttons under hero.
- **Refined.** Don't kill `+` entirely — every mainstream AI iOS app keeps a compose icon top-right (ChatGPT, Claude). Pure Arc-Search "input is the app" doesn't work for multi-thread products. **Demote `+` to top-right compose icon, only visible when not on Home.** Replace horizontal-tile scroller for All/Shared/Archived with a **segmented control or filter strip** — those are filters, not destinations. Status chips → one small-caps line, not pill chips. Cap project color/icon picker to 8 swatches × 30 symbols with a search field (Apple Reminders pattern).
- **Killed.** Nothing outright.
- **Missed.** **(a) Recents row of last 3 chats at the top of Home with a Resume affordance** — muscle-memory destination for returning users; ChatGPT iOS has been emphasizing this since v1.2026.040. **(b) Search across chats + projects + sources** in the Home header; Claude, ChatGPT, Gemini all ship this and you don't.

### Composer
- **Validated.** One-line ask copy, concrete prompt chips, send=filled circle with spring, send→stop while streaming, attachment shelf, model chip chevron, agent moves into overflow.
- **Refined.** Auto focus chip — distinguish by **filled vs outlined** (Perplexity mobile pattern), not just tint; WCAG 1.4.1 forbids color-only signaling. Respect Reduce Motion (cross-fade fallback). Council "thinking" tray needs **per-model TTFT, kill-one-model, "good enough — stop waiting"** — without these, one slow model tanks perceived speed.
- **Killed.** None. Edge to plan for: typing into composer mid-stream — ChatGPT iOS had this bug in 2024 and fixed it by locking the composer with a thin separator. Don't repeat.
- **Missed.** **(a) Slash commands** (`/council`, `/agent`, `/verify`, `/project`) — Raycast/Linear/Notion ship this; no mainstream AI iOS app does. Real differentiator. **(b) Paste-to-attachment at >5,000 chars** — ChatGPT shipped this May 2026; mobile-critical for long-doc paste.

### Model picker
- **Validated.** Two-chip max per row; Models|Council tab split (Copilot ships this as Chat|Counsel); per-model relative cost (Poe pattern); per-model Verified check (positioning-critical); specific search placeholder; quick-filter chips.
- **Refined.** Drag-to-reorder Council builder is correct **but ship "auto-Council" as default**, builder behind a `Customize` button — don't force assembly on first run. Make `Private` filter default-on and persistent for users who came for that reason. Add a second row of capability chips (Vision/Long-context/Code/Reasoning) — Claude and ChatGPT both do two rows.
- **Killed.** None.
- **Missed.** **(a) Per-model "last verified" timestamp** ("attested 2h ago"). Teaches users attestation is continuous, not a one-shot. Cash App / Stripe Dashboard "last reconciled" pattern. **(b) Favorites/pinned models** — ChatGPT picker has had this since 2025; Poe pins recents. A picker of 33+ models without favorites is dismissive of returning users.

### Project Context
- **Validated.** Kill the Library explainer + full-width Refresh button (pull-to-refresh is HIG); move add-link form above list or behind `+`; single overflow per row; shrink hero card to 140pt; tint file icons by type (with extension badge for color-blind users); empty state with drop target + button.
- **Refined.** Tabs — **three not four**. Claude iOS and Gemini Gems both fold notes into instructions, or files/sources into one. Four tabs on a sub-surface is iPad pattern, not iPhone. **Remove "Guided" pill entirely** — show instructions inline if present, hide if not.
- **Killed.** None.
- **Missed.** **(a) Per-source freshness indicator** ("synced 4h ago" / "stale — re-sync"). For a RAG-knowledge product this is the single biggest miss. Notion AI and Glean show it. **(b) "What this project knows" auto-summary** — system-generated 2-sentence summary at the top of the project, regenerated when sources change. Claude Projects has this experimentally on web; no iOS app ships it.

### Chat header
- **Validated.** Persistent attestation shield right of model chip — load-bearing for positioning. Cap title 2 lines + long-press to rename (Apple Mail pattern). Auto-generate titles (table stakes — ChatGPT/Claude/Gemini all do it; don't claim novelty). Tappable project breadcrumb. Source chip expands inline.
- **Refined.** Only render the source chip **when sources were actually consulted** and surface the count ("3 sources"). Empty source chips erode trust faster than no chip.
- **Killed.** None.
- **Missed.** **(a) Per-message attestation state** — a chat that started verified but had one fallback turn must show that per-turn, not just at the header. **(b) Tap-on-model-chip switches model for next message** without leaving the chat — ChatGPT and Copilot ship this; your current chip is informational only.

### Council answer
- **Validated.** All four items. Direct/Agree/Disagree/Next-step component with chevron-collapsible sections; per-model header pills with tap-to-switch view (Copilot pattern); disagreement-only export; ask-the-dissenters follow-up.
- **Refined.** **Only show sections that have content** — hide Disagree if all agreed. Empty sections teach users the structure is theatre. "Ask the dissenters" surfaces only when real disagreement was detected, and the button label describes what they disagreed about ("Ask why GPT disagreed on the timeline").
- **Killed.** None.
- **Missed.** **(a) Side-by-side full transcript view** — Poe multi-bot columns pattern, one swipe away from synthesis. Power users want raw, not synthesized. **(b) Per-claim confidence per model** — Anthropic's verbalized-confidence research is mature enough to surface. If GPT says "highly confident" on a number and Claude says "moderately confident," that's the kind of signal that justifies Council existing.

### Agent
- **Validated.** All five. Consumer-readable subtitle copy; pills → prefill templates; Auto skills promoted; auto-bind active project; in-thread step-by-step progress card.
- **Refined.** Progress card — **show last 3 steps inline + collapsible "+N more" + sticky current-step banner**. Otherwise 50+ steps eat the thread.
- **Killed.** None.
- **Missed.** **(a) Pausable/resumable agent runs** — ChatGPT Codex mobile and Claude Code desktop both ship `/pause`; your design assumes stream or done. **(b) Inline approval gates** — destructive/expensive actions surface a card in-thread, not a modal. Linear's deploy approvals card is the reference.

### Security/Attestation
- **Validated.** Top-row Verify-on-device button; Share proof exports attestation-only JSON; QR-to-verifier-with-preloaded-transcript (novel — closest reference is Signal safety-number QR); "Why this matters" collapsible.
- **Refined.** "1 of 1 verified · GLM 5.1-FP8" → **"Verified · GLM 5.1-FP8 · Intel TDX"** — three facts, each readable, each tappable for detail. "1 of 1" is opaque outside an internal team.
- **Killed.** None.
- **Missed.** **(a) Attestation reproducibility test** as a verification primitive — "send same prompt to same model, compare attestations" button per message. **(b) Hardware identity display** — specific GPU model + firmware version that ran inference. Phala and Tinfoil show this on verifier pages; in-app is the next step.

### Cross-cutting
- **Validated.** Semantic color tokens with Blue cap of 3 per screen; motion tokens with springs (use iOS 26 Liquid Glass defaults: response 0.4, damping 0.5); standardized radii; Blue→Sky hero gradient one-per-screen; auto-titles; app-icon variants (iOS 18+ supports natively); Live Activity for attestation freshness (killer iOS surface, unique moat); App Intents (mandatory in 2026 for Apple Intelligence visibility); widgets; iPad split view; branch view for regenerate (third-party tools exist, no mainstream app ships it well); per-message timestamp on long-press (HIG-standard).
- **Refined.** Motion tokens — **honor Reduce Motion** with cross-fade fallback. #EEEEEB Off-White is **light-mode only** — ship a parallel dark-mode palette. Beginner mode hiding Agent/Council/NEAR Cloud — **make it a setting with onboarding choice ("First time? Beginner / Power"), not a hidden state**. Microsoft Copilot got pilloried for hidden beginner mode in 2026.
- **Killed.** None.
- **Missed.** **(a) VoiceOver + Dynamic Type pass** at xxxLarge — none of your 70 items touch accessibility beyond touch targets, and Apple HIG requires Dynamic Type support. **(b) Haptics map** — Perplexity uses haptic-responsive focus selector; absence reads as cheap. **(c) Drafts persistence** — Cash App and Mail restore drafts on background; mobile AI apps frequently lose them.

### Three new features
- **Validated.** Quick Council (long-press/swipe to re-ask any message with Council — Slack Forward / Linear Convert pattern). Signed Snippet (strongest single trust-building feature; one-line plain-text format `GLM 5.1-FP8 via NEAR · verify: near.ai/v/abc123` is Twitter/email-safe). Attestation Diff (real and novel — frame as "model behavior changed since last session," not "drift").
- **Missed.** **Signed transcript publish.** Beyond Signed Snippet, let users publish a full chat as a public verifier page with attestation chain baked in. Gateway to "tax advisor saw this / doctor saw this / lawyer saw this." Nobody else can ship this — they don't have TEE attestation.

## The 12 highest-leverage moves, ranked

1. **Persistent attestation shield + per-message attestation state.** Load-bearing for positioning; visible on every screen.
2. **Signed Snippet with one-line verifier URL.** The single most viral feature in the punchlist — works on Twitter, email, Slack.
3. **Council thinking tray with per-model TTFT + stop-waiting affordance.** Turns Council from gimmick to useful default.
4. **In-thread agent progress card with last-3-steps + sticky banner + pause + inline approval gates.** Wins against Codex mobile and Claude Code mobile.
5. **App Intents (Start verified chat, Ask about selected text, Open shared link).** Without this you're invisible in Apple Intelligence 2026.
6. **Lock-screen Live Activity with attestation freshness.** Ambient trust signal nobody else has.
7. **Auto-Council default with "Customize" button.** Council becomes one-tap, not three-tap.
8. **iPad split view with persistent attestation panel.** Most underused surface in the AI chat category. Pure moat.
9. **Search across chats + projects + sources in Home header.** Closes the obvious gap vs ChatGPT/Claude/Gemini.
10. **Per-source freshness indicator** in Project Context. RAG credibility hygiene; competitors mostly skip it.
11. **Slash commands in composer.** Linear/Notion/Raycast pattern; no AI chat ships this well on mobile.
12. **Reproducibility test button + Attestation Diff.** Verifiable inference made concrete and testable.

Of these twelve: four (1, 2, 6, 12) are pure positioning moves only you can ship; four (3, 4, 7, 8) turn novel features into defensible defaults; four (5, 9, 10, 11) close credibility gaps with the leaders. Healthy ratio — most punchlists are 80% catch-up and 20% differentiation; yours is the inverse.

## Key sources (full set in agent transcript)

- Apple HIG: Tab Bars, Toolbars, Motion, App Intents
- iOS 26 / Liquid Glass design references (Apple Developer, Create with Swift, Donny Wals)
- ChatGPT iOS release notes (Releasebot, May 2026), Codex mobile preview (OpenAI Community)
- Claude iOS guide (Beginners in AI), Claude Project knowledge base docs, Claude Agent SDK + Xcode announcement
- Perplexity Focus Modes (Perplexity AI Magazine), Comet iOS upgrades (9to5Mac May 2026)
- Microsoft Copilot Multi-Model "Model Counsel" (Windows Forum, Microsoft Community Hub)
- Gemini IO 2026 redesign (TechCrunch, 9to5Google)
- Poe Multi-bot chat (Poe Blog)
- NEAR AI verification docs, Private Inference docs, "Building Next-Gen Infrastructure with TEEs"
- Phala and Chutes confidential-compute reference pages
- Material 3 Expressive motion research (May 2025)
- Linear, Things 3, Stripe Apps empty-state patterns
