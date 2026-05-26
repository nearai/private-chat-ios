# NEAR Private Chat iOS — Archive-25 Feedback Pass

Date: 2026-05-25 (afternoon, post-2pm captures)
Inputs: 11 screenshots from `Desktop/Archive.zip` (2026-05-25 14:04-14:10), user feedback callouts, fresh web research on legal-acceptance copy, capability-mismatch UX, empty-state chip patterns, and iOS 26.4 Liquid Glass.

Status note: superseded by `NEARPrivateChatIOS-agentic-default-design-spec-2026-05-25.md` where the two conflict. Specifically, the permanent composer capability strip, pinned hero status capsules, and `Open Project ▾` hero button proposals below are reversed by the agentic-default model. Keep this file as diagnostic record and copy-level evidence, not the build order.

Implementation note: the first code pass removed the top-level legal "attestation required" copy, retired the `5 bullets / Find risks / Draft memo` chips from active UI, and changed NEAR Cloud routing so the app can supply web/project context before the model call.

User's four callouts, addressed first, then deeper design work below.

---

## 1. "Copy not good on top" + "attestations required is not exactly how these things work"

**The bug.** Auth screen reads `Legal attestation required` and the bullets explain Terms acceptance. The product *also* uses the word **attestation** for the actual TEE proof (Intel TDX / NVIDIA confidential compute signatures). Same word, two unrelated meanings, both surfaced at install — that's a brand-defining word collision on the very first screen.

**The truth about how attestation actually works** (worth fixing because the bullets misframe it):

- A TEE attestation is a **runtime hardware proof** — the gateway produces a signed quote of the firmware + the loaded model binary, and the client verifies that signature against known measurements. It is not "consent given by the user," it is "proof emitted by the machine." Calling user consent an "attestation" inverts the term.
- "Required before sign-in" is also wrong as framed. Attestation is checked **on each session / each route**, not gated to login. What's required before sign-in is **Terms acceptance** — a legal artifact.
- The bullet "Cloud premium models are anonymized/proxied, not attested" is correct but reads like fine print. It should be a *capability statement* in the model picker, not a buried bullet on the auth screen.
- "Attestation is proof of serving environment, not proof that an answer is true" — this is the only honest bullet on the page, and it's the most important one to *keep* — but it belongs in the in-app Verification sheet, not in a legal-acceptance flow.

**Fix.** Rename the screen and split the responsibilities cleanly.

```diff
- Legal attestation required
+ Terms & Conditions
-   Accept the current Terms before sign-in.
+   To use NEAR Private Chat you need to accept these
+   terms. Continued use is acceptance.

  - Required before sign-in
- - Applies to private chat, Cloud models, files, sharing,
-   web grounding, LLM Council, or IronClaw agents.
+ - Covers private chat, Cloud, files, sharing, web,
+   LLM Council, and IronClaw agents
- - Cloud premium models are anonymized/proxied,
-   not attested.
+ - Cloud models route through a privacy proxy.
+   They don't carry TEE proof — see route details
+   inside chat.
- - Attestation is proof of serving environment, not
-   proof that an answer is true.
+ - Cryptographic proof shows where a model ran,
+   not whether its answer is correct.
- - Agent actions and connected keys remain your
-   responsibility.
+ - You stay responsible for what agents do and any
+   keys you connect.

  [ Review terms ]
- [ Accept and continue ]
+ [ Agree & Continue ]
```

Reasoning, with citations. Apple Pay's Wallet flow uses literal copy `Accept the Apple Pay & Wallet Terms`; Cash App and Robinhood do the same — verb + agreement-tied-to-action. Nobody in iOS uses "attestation" for legal acknowledgement; that word is reserved for cryptographic state. Apple's PCC docs are the strongest precedent: *"Attestation enables a user's device to securely verify the identity and configuration of a Private Cloud Compute cluster"* — when Apple talks to users about this, they say **verify**, never attest. Pattern is the same across GitHub's signed-commit "Verified" badge, Signal's safety-number "Verified" check, 1Password's "Verified Domain". The right verb is **verify**, the right badge state is **Verified**, the right legal step is **Agree**.

Bonus copy fix on screen 3 (the hero card): `Private AI chat with cryptographic proof, shared links, projects, and agent power when you need it.` This sentence stacks four product features behind a noun phrase and ends in a cliché. Try:

> **NEAR Private Chat**
> Private AI you can verify. With projects, sharing, and agents when you want them.

Two sentences. Lead with the differentiator. Drop "power when you need it" — it's filler.

---

## 2. Are `5 bullets / Find risks / Draft memo` really the best chips?

No. Three problems with the current set.

**(a) They mix grammatical categories.** "5 bullets" is an output format. "Find risks" is a verb phrase. "Draft memo" is a verb-object pair. A user reads the row and can't tell what the affordance is — pick a format, pick a task, or pick an action.

**(b) They are not project-aware.** The composer says `Agent Workspace is selected`, so the chips should reflect that this project has files, links, and instructions. None of the three do.

**(c) They lean editorial.** "Find risks / Draft memo" are MBA-deck verbs. Most NEAR Private Chat users aren't writing risk memos.

**Fix — verb-first, task-shaped, project-aware, three chips max.**

When a project is loaded:
- `Summarize my latest doc in this project`
- `Compare two files in this project`
- `Draft a reply using my saved notes`

When no project is loaded (cold composer):
- `Explain this article` *(invites paste)*
- `Plan my next 24 hours`
- `Write a follow-up to a meeting`

Hide chips entirely on the third opened composer of a session — by then the user has muscle memory and the chips become visual clutter. This is what Gemini's Neural Expressive (May 2026 redesign) did: removed chips at cold start and bet on greeting + tool sheet. Perplexity uses full-sentence Discover-feed cards rather than chips. Raycast AI Commands are verb-first by construction. NN/g's guidance: prompt controls work *only* when they teach what the AI can do — formats don't teach.

**Don't ever ship `5 bullets`.** Format-only chips are the wrong abstraction.

---

## 3. No web or project access on NEAR Cloud — fix this immediately

This is the most damaging UX failure visible across screens 5, 6, 7. The user:

1. Composes a prompt while `Agent Workspace is selected` and the focus chip strip shows `Auto / Web / Project / Research`. Reasonable expectation: the model can use these.
2. Sends.
3. Lands on a chat where the assistant apologizes for 90 seconds about why it can't see project files or search the web. The user has to read the apology, choose a fix from three bullets, then restart the prompt.

This is a route-capability mismatch surfaced *after the send*. Every major AI chat app moved this kind of surfacing into the composer in 2025-2026. Three layered fixes, in order of preference:

### 3a. Auto-route on capability request (best fix)

When a user selects `Claude Opus 4.7 (Cloud)` and then attaches a project, taps `Project` focus, or types something file-aware, **auto-route this specific request through a TEE-capable path** that *does* have file/web access. The model name stays, the underlying serving lane changes. This is how ChatGPT's Auto/Fast/Thinking switcher works — the user picks a quality tier, the runtime picks the route. The user never sees an apology because the request is silently routed to a lane that can answer it.

If a NEAR Private model with similar capability exists, drop in. If no equivalent exists, fall through to 3b.

### 3b. Recast by agentic-default: no permanent pre-send strip

The earlier permanent strip proposal (**Project · Web · Verified**) is rejected for the default UI. The orchestrator picks route/tools/proof before send; users should not toggle Web/Files/Verified before asking.

Fallback UX only: if the orchestrator detects a hard conflict it cannot safely auto-resolve, show one inline recovery chip below the input, such as `This needs project files — switch to Private?`. Tap opens a short sheet with a single primary CTA. No persistent capability strip.

This still eliminates the apology turn, but the composer stays quiet until there is a real conflict.

### 3c. Live capability lint on the prompt (delight layer)

When the user types tokens like `summarize this file`, `read my doc`, `search`, `browse` while the current route lacks the relevant tool, surface a small inline chip below the input: `This route can't read files — switch?` with one tap to swap routes. Latency-free recovery. Nobody in the field ships this yet.

**Banned from this product going forward:** assistant turns that apologize for what the chosen route can't do. If you can't fix it pre-send, the route shouldn't be selectable while the user is composing a prompt the route can't answer. The screen 6 / screen 7 chat content — a thoughtful, well-formatted apology — is *correct as text* and *wrong as UX*. It should never have been allowed to be the first assistant response.

---

# Deeper design pass — beyond the four callouts

## Hero card (s3, s4)

The hero card is the strongest brand moment in the app and the two visible versions disagree with each other.

- On auth (s3), it says `NEAR Private Chat / Private AI chat with cryptographic proof, shared links, projects, and agent power when you need it.` with three chips below: `Proof · Private · Shareable`.
- On home (s4), it says `NEAR Private Chat / Using Agent Workspace` with `Ask · Project` and small caps `PROOF READY / WEB ON`.

Two different layouts, two different copy registers, two different identity claims. Pick one hero pattern and repeat. Superseded diagnostic mock:

```
[ N ]  NEAR Private Chat
       Private AI you can verify.

       [ Verified · GLM 5.1 ]  [ Project: Agent Workspace ]

       ┌───────────────────────────────────┐
       │ Ask                            →  │
       │ Start a private chat              │
       └───────────────────────────────────┘
```

Agentic-default replacement: no pinned status capsules on Home. Use one primary `Ask NEAR` card and one plain-language sentence: `Ready to answer, research, or take action.` Drop `WEB ON`, `PROOF READY`, model names, and project capsules from the default Home hero. The shared-link feature should be discovered when needed, not previewed at install.

## Auth screen — three other problems past the legal-attestation rename

1. **No "skip for now" affordance for shared-link entry.** The terms gate blocks the unauthenticated shared-link path that the prior audit identified as a key entry point. Either move the terms acceptance to first-message-send or add a "Just opening a shared link" escape.
2. **`Review terms` link sits inside the same card as the action button.** Tactile risk — easy to tap the wrong one. Separate the link as a footer below the CTA, smaller, secondary tint.
3. **Bullet list has six items.** Cut to four maximum on a legal screen. The reader is in agree-and-go mode, not study mode.

## Home (s4)

Strong improvements over earlier passes — filter strip (`All 46 / Shared 1 / Archived`), Resume row, Projects with `+ New`, no dev-named projects visible. Remaining problems:

1. **`PROOF READY / WEB ON` small caps below the Ask card** is dev-console language masquerading as status. It also competes with the Verified state idea. Agentic-default replacement: `Ready to answer, research, or take action.` If web is on by default, don't surface it.
2. **`Ask · Start a private chat` is two things on one row.** "Ask" is the verb, "Start a private chat" is the subtitle. The arrow rightside is a third visual element. Simplify to: full-width Ask button with `→` and no subtitle. Subtitle inside a button reads as a tooltip and adds chrome.
3. **`Project` button is half-width below Ask.** Agentic-default deletes this button from the Home hero. Project access moves to the Projects list/current project row. If no project exists, the only creation affordance is `+ New` in the Projects header.
4. **The hero card edges into the safe-area top.** On the latest iOS 26 with Liquid Glass, hero cards should respect a 12pt top inset so the system status bar (signal, wifi, battery) doesn't visually merge with the card on light mode.
5. **`+ New` Project trigger is right-aligned in the Projects section header.** Good. Make it consistent across the Resume and Workspace sections too (currently absent).

## Composer (s5)

The composer is the surface most affected by the four user callouts and should change the most.

Superseded diagnostic mock:

```
┌─────────────────────────────────────────┐
│  ←       New chat                       │
│  [ GLM 5.1 ▾ ]  [ Verified ]      [ … ] │
│                                         │
│  [N]  What do you want to ask?          │
│       Agent Workspace selected.         │
│                                         │
│   ⏵ Summarize my latest doc in this     │
│     project                             │
│   ⏵ Compare two files in this project   │
│   ⏵ Draft a reply using my saved notes  │
│                                         │
│                                         │
│                                         │
│                                         │
│                                         │
│  Project ▣   Web 🌐   Verified 🛡          │
│  ┌─────────────────────────────────┐   │
│  │ Summarize Agent Workspace's…    │   │
│  │                            [↑]  │   │
│  └─────────────────────────────────┘   │
│  📎                                     │
└─────────────────────────────────────────┘
```

Superseded notes from that mock:
- Header model/proof chips move to the answer footer.
- Verb-first project-aware chips remain valid.
- The permanent Project/Web/Verified strip is deleted.
- Send button stays as filled brand-blue circle when input is non-empty.
- Project context appears as breadcrumb/detail, not a separate control row.

Agentic-default replacement: the default composer has paperclip + input + send only. Model/proof/source controls move behind `…`/Details, and the orchestrator picks tools. Verb-first chips remain valid, but the permanent Project/Web/Verified strip is deleted.

## Chat (s6, s7)

The apology-turn UX is fixed at the source by the orchestrator. The chat itself shows a few more issues:

1. **Model chip says `Claude Opus 4.7` but the secondary line says `NEAR Cloud · NEAR Cloud · Agent Workspace`.** `NEAR Cloud · NEAR Cloud` is a bug — same value twice. Should read: `Cloud · Agent Workspace` or `Cloud route · Agent Workspace`. Audit anywhere `route` and `provider` are both rendered to dedupe.
2. **`Anonymized` chip is the wrong word.** Anonymized is something done to user data; what's happening here is that the *route* is proxied. Label as `Proxied route` or `Privacy proxy`. Otherwise users think you're anonymizing them when actually you're using a proxy server.
3. **Footer below the assistant message reads `Claude Opus 4.7 runs through NEAR Cloud with anonymized provider forwarding. It is not NEAR Private TEE-attested and gets no in-app file or web access.`** This is honest but reads like a compliance disclosure. Under agentic-default, this footer is only a fallback if the orchestrator cannot prevent the mismatch. Preferred footer: `Cloud · Claude Opus 4.7 · Privacy proxy · No project files`.
4. **The composer placeholder changes to `Ask Claude Opus 4.7`** — adopting the model name into the placeholder is a Poe/ChatGPT pattern and it's fine. Keep.

## Agent chat (s8)

1. **`No TEE` chip on the chat header** is the negative-state version of the `Verified` chip. Consistent with the rest of the system — fine. But `No TEE` is engineering acronym. Canonical default behavior: hide negative proof state from the header and show answer-footer `unverified`, `private_`, or `proxied` via the shared ProofCapsule.
2. **`Agent route` subtitle under the model chip** is good. Same pattern works for Cloud / Private / Council routes.
3. **`Running IronClaw Mobile` with the three-dot loading indicator** — this is the in-thread progress UI the prior audits called for. Good. But it stays as a single one-line state. The next pass should expand this into the multi-step run card (sticky current step + last 3 + approvals + final summary).
4. **User sent `hello?`** after the first prompt and got a second `Running IronClaw Mobile` block. This means the agent doesn't queue or coalesce user messages while it's already running. Either gray out the input while a run is in flight or render the second user message inside the same run card as additional context.
5. **Two consecutive blue bubbles from the user** with no assistant turn between — this is what the message log looks like when an agent is mid-run. Visually it reads like a broken conversation. Suggested: render the in-progress agent block more prominently so the gap between user-bubble-1 and user-bubble-2 contains a clear "agent working" island.
6. **Bottom focus chip strip is still `Auto · Web · Project · Research`** even on Agent route. Agentic-default deletes this strip. Agent controls appear only inside the in-thread agent offer/run card.

## Account (s9, s10, s11)

1. **`Capability Center` is the strongest IA improvement in the app.** `Private ready · Cloud connected · Agent phone ready` is a clear three-line state read. Keep this exact pattern.
2. **`Run Setup Again` under `Composer Setup` section.** The section heading "Composer Setup" is wrong — setup affects more than the composer (model defaults, project starters, route choice). Rename section to `Setup`.
3. **Helper paragraph below `Run Setup Again` is two sentences.** Cut to one: `Updates source, model, and starter defaults. Your chats and projects stay.`
4. **`Web Search` and `Large Paste as File` toggles** under "Composer" — these are real, but the toggle for Web Search at the account level conflicts with the per-message Web toggle in the composer. Pick a layer: either web is on/off per chat (composer) or per account (settings), not both. Recommend per chat with no account-level toggle.
5. **`System prompt` field empty by default.** Field is functional but with no hint of what it does. Add a one-line placeholder: `Optional. Add an instruction every chat uses.`
6. **Models & Billing block (s10) lists three tiers (starter / pro / free) as a flat list.** This is dev billing. For end users, show *current plan* + *what you can do* + *Upgrade* CTA. Hide the matrix behind "See all plans".
7. **`Renews 2026-06-22T20:20:21Z`** in raw ISO timestamp is engineering output, not user copy. Render as `Renews on Jun 22, 2026`.
8. **`Refresh Billing` is a blue link** under the billing block. Make it a small secondary text button, not a primary blue link — refresh is not a primary action on a settings screen.
9. **`Power Tools` section (s11) is a real win.** The pattern — explain in two sentences, big blue `Show Power Tools` CTA, then four list rows beneath — is right. But the four rows below are already visible *even when Power Tools is hidden*. Either hide the four rows by default (so the CTA actually toggles), or remove the CTA and let the four rows live there directly. Right now the CTA is a no-op visually.
10. **`Sign Out` in red** at the bottom is fine, but it sits next to the four Power Tools rows with no visual separation. Add a section divider or move Sign Out to its own group with a `Danger Zone` heading (Linear, Notion pattern).

---

## iOS 26.4 Liquid Glass discipline (May 2026 settled spec)

Apple shipped iOS 26.4 in April 2026 with two customization toggles that codify the readability fixes NN/g pushed for after 26.0. The settled spec as of May 2026:

- **Material:** only `.glassEffect(.regular, …)`. `.thick` is deprecated. `.thin` is reserved for over-image overlays.
- **Capsule pills:** padding 10pt vertical / 14pt horizontal. Hero cards: corner radius 20pt outer, with inner radius concentric (outer minus inner padding).
- **No glass-on-glass nesting** past two layers — visual mud.
- **Respect the system opacity toggle** users now control in Settings → Accessibility. Don't override.
- **Tab/nav bars float and shrink-on-scroll** — never bezel-pinned.
- **Model pickers >5 options use the picker-screen pattern** (list item + chevron → full page), not pull-down menus.
- **Status pills:** green tint for verified, neutral grey-glass for cloud, never red (reads as alarming).

NEAR Private Chat in the screenshots is *mostly* on-spec — the hero card, chips, and segmented controls all use the right material and radii. Three places to tighten:

- The `Sign Out` red row in s11 should not use glass-tint red; reserve red for true destructive confirmations.
- The blue full-width `Show Power Tools` button in s11 is non-glass solid blue. Either glass it (capsule with brand tint) or commit to solid blue everywhere primary appears.
- The capsule chips on the hero card (`Proof · Private · Shareable` on auth, `PROOF READY / WEB ON` on home) use different metrics. Standardize to one chip token.

---

## Concrete fixes, ranked by leverage

1. **Auth screen rename to `Terms & Conditions`** + tightened bullets (above). Kills the word collision at install.
2. **Orchestrator before send** + auto-route Cloud/project/web requests through a capable private route when possible. Kills apology turns at the source without a permanent capability strip.
3. **Replace chips with verb-first project-aware set.** `5 bullets / Find risks / Draft memo` retired.
4. **Reserve `attestation` for engineering only.** In-app, the badge is `Verified` (trust-green capsule). The action verb is `Verify`. Apply across header chips, share footers, exports.
5. **Dedupe `NEAR Cloud · NEAR Cloud · Agent Workspace`** sub-line and rename `Anonymized` → `Privacy proxy` or `Proxied route`.
6. **Compress route-limit copy into a short answer footer** only when the orchestrator cannot prevent the mismatch entirely. This is fallback copy, not the primary fix.
7. **Replace home hero `Ask · Start a private chat · → · Project`** with a single `Ask NEAR` CTA and the sentence `Ready to answer, research, or take action.`
8. **Render `Renews 2026-06-22T20:20:21Z` as `Renews Jun 22, 2026`** and audit every raw datetime string in the app.
9. **Hide the four Power Tools rows behind the `Show Power Tools` CTA** so the toggle actually toggles.
10. **Adopt the iOS 26.4 settled Liquid Glass spec** (above) and run a visual-diff pass against the existing tokens.

If those ten land, the next demo cut shows a meaningfully calmer, more truthful app with the same feature surface. The orchestrator move (#2) removes the single most damaging UX failure currently visible.

Canonical proof state for engineers:

```swift
enum ProofState {
    case unknown
    case verifying
    case verified
    case stale
    case mismatch
    case private_
    case proxied
    case unverified
}
```

---

## Sources (web research, May 2026 cutoff)

- Apple Pay Wallet Terms — apple.com/legal/internet-services/apple-pay-wallet/us/
- Apple Security Research: Private Cloud Compute — security.apple.com/blog/private-cloud-compute/
- GitHub: About commit signature verification
- Signal: Safety Number Updates
- Red Hat: Attestation in confidential computing
- OpenAI: ChatGPT Release Notes; GPT-5.5 in ChatGPT (Auto/Fast/Thinking)
- The Decoder: Auto/Fast/Thinking toggles in GPT-5
- Claude Help: Enabling and using web search; Claude App Complete Guide 2026
- 9to5Google: Gemini Neural Expressive (May 2026); Gemini full redesign
- Perplexity May 2026 Release Notes
- Raycast Manual: AI Commands
- NN/g: Prompt Controls in GenAI Chatbots
- Mobbin: Empty State UI Design
- Apple Developer: Liquid Glass; Apple Newsroom: Liquid Glass intro
- NN/g: Liquid Glass Is Cracked
- 9to5Mac: iOS 26.4 Liquid Glass updates (April 2026)
- AppleInsider: iOS 26.1 Liquid Glass opacity setting
- learnui.design: iOS 26 Design Guidelines
- Medium / Conor Luddy: Liquid Glass SwiftUI Reference
- Level Up Coding: Liquid Glass Design System in SwiftUI
- 1Password: March 2026 verified-domain announcement
