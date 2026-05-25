# NEAR Private Chat iOS Design Review Spec

Date: 2026-05-24
Status: updated with product direction to prefer SF Pro and ignore the NEAR AI brand guidelines as binding design rules.

Inputs:
- Fresh screenshots: `review-artifacts/screenshots-2026-05-24-fresh/`
- Fresh audit: `review-artifacts/NEARPrivateChatIOS-fresh-screenshot-feature-audit-2026-05-24.md`
- Competitive/onboarding roadmap: `review-artifacts/NEARPrivateChatIOS-competitive-onboarding-roadmap.md`
- Optional reference only: `/Users/abhishekvaidyanathan/Downloads/NEAR_AI_BrandGuidelines_v01.pdf.zip`

Note: the zip contains the PDF only, not separate production-ready icon assets.

## Executive Decision

This app should be product-led, iOS-native, and SF Pro-first. Ignore the NEAR AI brand guidelines as a binding source for typography, palette, gradients, layout, or tone.

The only part of the brand PDF worth selectively mining is iconography or mark ideas if they make the product better, especially around private chat, verification, and trust. Even then, treat the PDF as inspiration. Do not force the app into the brand system.

Settled decisions:
- SF Pro is the product typeface. Do not add FK Grotesk.
- Keep native iOS affordances where they improve clarity, accessibility, and trust.
- Use the existing app palette as a starting point, but let product UX, contrast, and hierarchy decide final colors.
- Keep or refine `verifiedGreen`; attestation is allowed to have its own trust color.
- Use custom iconography only when it is clearer than SF Symbols and available as a proper asset.
- The top product priorities remain: attestation visibility, share safety, home density, taxonomy cleanup, undo, accessibility, and stream resilience.

## Current Implementation Status

Already in good shape:
- The app is already SF Pro-based.
- Setup, home, composer, model picker, Agent workspace, Project Context, and Account were freshly captured.
- Focus chips, model/Council tabs, prompt chips, delete confirmation, Developer disclosure, attestation education, signed export, and verifier tooling are now implemented.
- The app already has useful color tokens in `NEARPrivateChat/Models.swift:2309`.
- `verifiedGreen` exists in `NEARPrivateChat/AttestationStatus.swift:298`, which is directionally right for trust.

Still open:
- Phone chat compact header still does not show a persistent attestation shield.
- Home still has too many first-screen jobs: search, Ask, Agent, Project/Context, workspace rows, projects, recents, account footer, and toolbar plus.
- Public-link sharing is still too abrupt without preview, expiry, or undo.
- Project taxonomy still exposes `Sources / Library / Guide / Saved` instead of simpler language.
- Blue is overused across selection, links, active chips, info badges, icons, CTAs, message bubbles, and verification.
- The app does not yet have a documented visual hierarchy for action colors, trust colors, secondary states, and destructive states.

## Design Direction

### Tone

Quiet, capable, secure, modern, and direct. This should feel like a serious private AI work tool, not a marketing page and not a developer console.

### Typography

SF Pro is final.

Implementation guidance:
- Use native Dynamic Type styles wherever possible.
- Avoid custom font loading.
- Use weight and spacing for hierarchy rather than decorative type.
- Keep dense UI readable at small sizes.
- Do not use FK Grotesk in product UI, hero cards, sheets, settings, exports, or verifier pages unless product reverses this decision later.

Suggested type ladder:

```swift
typeDisplay   = .largeTitle.weight(.bold)
typeTitle     = .title2.weight(.semibold)
typeHeadline  = .headline
typeBody      = .body
typeCaption   = .caption
typeMicro     = .caption2.weight(.semibold)
```

### Color

The palette should serve hierarchy, trust, and contrast. It does not need to comply with the brand PDF.

Keep semantic roles:
- Primary action: current brand blue or a refined action blue.
- Trust/verified: current `verifiedGreen` or a refined green/teal with WCAG AA contrast.
- Warning/stale: system orange or a clear neutral-warning token.
- Destructive: iOS system red.
- Background: the current warm off-white direction is good; pure white is acceptable only if contrast/layout benefits.
- Secondary text: darken weak grey metadata until it passes contrast.

Recommended semantic tokens:

```swift
primaryAction        = Color.brandBlue
trustVerified        = Color.verifiedGreen
trustFreshAccent     = Color.brandSky
warning              = Color.orange
destructive          = Color.red
surface              = Color.appBackground
panel                = Color.appPanelBackground
secondarySurface     = Color.appSecondaryBackground
border               = Color.appBorder
textPrimary          = Color.primary
textSecondary        = Color.secondary
```

Longer-term cleanup: views should consume semantic tokens, not raw `Color.brandBlue` everywhere. Do not block current product work on a token rename, but make this the direction for the visual pass.

### Iconography

Default to SF Symbols for product controls. SF Symbols are native, accessible, scalable, and consistent with SF Pro.

Optional custom iconography:
- A Private Chat shield/chat-bubble mark may be worth extracting or recreating as a clean vector asset if it is visually strong.
- Use it only for trust/verification surfaces, not everywhere.
- It must work at 16, 20, 24, and 32pt sizes.
- It must have monochrome, filled, and outline variants or render cleanly with SwiftUI tint.
- It must not force adoption of the PDF's palette, type, or lockup system.

Do not use brand lockups as product UI unless they are cleaner than current text. The app name can remain normal SF Pro text.

### Shape And Layout

Recommended tokens:
- Cards: 8-12pt continuous radius.
- Buttons: 8-10pt continuous radius.
- Chips: capsule/pill.
- Keep cards out of cards.
- Use stable heights for toolbars, chips, model rows, and composer controls so state changes do not shift layout.

## Design Principles

1. One primary action per screen.
2. Attestation should be visible, not hidden in overflow.
3. Sharing should explain consequences before publishing.
4. Project/context language should use fewer terms.
5. SF Symbols first; custom icons only for trust signature moments.
6. Color communicates role: action, trust, warning, destructive, secondary.
7. Motion is restrained and respects Reduce Motion.
8. Accessibility is not a cleanup pass; it is part of every UI packet.

## Attestation Visual Grammar

Attestation can use a distinct trust color. Keep or refine `verifiedGreen`; do not replace it just to satisfy the brand PDF.

| State | Visual |
| --- | --- |
| `verified fresh <2m` | Shield/check chip in trust green, freshness text `<2m` |
| `verified recent <1h` | Shield/check chip in trust green or blue-green, freshness text `<1h` |
| `stale` | Shield/clock in orange or neutral warning |
| `mismatch` | Shield/exclamation in red-orange or high-contrast warning |
| `unavailable` | Grey shield outline or `No proof` label |
| `unknown` | Grey outline shield; tap invites fetch/refresh |

Required surfaces:
- Compact chat header shield next to the model chip.
- Per-message assistant chip for attested routes.
- Model picker badge for covered private models.
- Signed export header.
- Verifier web page hero.
- Public share preview and public shared-chat seal.

Interaction:
- Tap opens the existing Security sheet.
- Long press can later open a dossier sheet: route, model hash, gateway, nonce, timestamp, signing algorithm, transcript/export verification affordance.

## Screen Specs

### 00 Setup

Current state: substantially improved and account-scoped.

Update spec:
- Keep SF Pro.
- Keep the plan preview.
- Move IronClaw/Council under Advanced if first-run comprehension tests poorly.
- Make Skip explicit: "Use recommended private defaults."
- Keep row styling calm; reduce decorative status chips if they compete with choices.

### 01 Home

Current state: better chip grammar and hidden zero counts, but still too dense.

Update spec:
- Hero has one primary CTA: Ask.
- Remove or demote toolbar plus.
- Agent and Context become secondary actions exposed by setup intent, selected project, or agent model.
- Status line becomes one quiet row: `Privacy: verified · Web: on · Sources: 1`.
- Project rows get icon/color, but the color picker can be product-led rather than brand-constrained.
- System rows (`All Chats`, `Shared With Me`, `Archived`) must be visually separate from user projects.
- Account footer should move toward top-right account/settings affordance to reclaim bottom list space.

### 02 Composer

Current state: focus row, prompt chips, context strip, attachment strip, and send/stop state are now good.

Update spec:
- Keep the single Focus row: Auto, Web, Files, Links, Research.
- Active focus chip uses primary action color only for deliberate selected modes; Auto can be neutral.
- Model chip gets a chevron and, on attested route, a trust shield.
- Add compact header attestation shield; the composer itself should not carry all trust state.
- Send is primary color when ready, grey when empty, red stop while streaming.

### 03/04 Model Picker And Council

Current state: Models/Council tabs implemented.

Update spec:
- Keep segmented `Models | Council`.
- Summary card max: provider, plan, route/trust. Move the rest to Details.
- Do not show the Council card inside the Models tab.
- Add verified-route shield to private model rows when attestation covers that model.
- Add relative cost only when pricing data is accurate and stable.

### 05 Agent Workspace

Current state: one of the strongest surfaces.

Update spec:
- Keep the darker/immersive agent card if it feels better than a forced bright gradient.
- Capability pills must choose one role: static labels or interactive filters. If static, remove button-like styling.
- Elevate `Skills: Auto` near the start action.
- Reuse the context affirmation strip pattern in normal chat/project composer.

### 06 New Project

Current state: clear but missing identity affordances.

Update spec:
- Add color picker with tasteful product palette, not brand-limited swatches.
- Add small icon picker, SF Symbols first.
- Preview the project row while editing.
- Add default source/tool mode if available, but keep it optional.

### 07/08 Project Context And Library

Current state: strong hero; taxonomy still too broad.

Update spec:
- Rename tabs to `Sources / Files / Instructions / Notes`.
- `Library` becomes `Files`.
- `Guide` becomes `Instructions`.
- `Saved` becomes `Notes`.
- Add-link form moves above the link list or behind an `Add link` action.
- `Refresh Library` becomes a small refresh icon in the Files section header plus pull-to-refresh.
- File/link deletes need undo or confirmation.
- Project hero uses project icon/color once project identity lands.

### 09 Account

Current state: Developer disclosure is fixed; screen still mixes account, diagnostics, billing, integrations, imports, and settings.

Update spec:
- Keep identity card at top.
- Group settings as Composer, Privacy, Models, Integrations, Developer.
- Keep Developer plumbing behind disclosure.
- `Run Setup Again` stays with the clarified copy, but it should not be the dominant settings action.
- Keep helper text to one sentence per section.

### Share

Source-reviewed, not cleanly recaptured.

Update spec:
- Public link must not be one-tap final. Add preview and confirm.
- Preview includes title, messages, sources, permission, expiry, account metadata note, and attestation seal.
- `Invite People` is visible next to public link.
- Disabling public link needs undo or confirmation.

### Security

Source-reviewed, not cleanly recaptured.

Update spec:
- Keep existing education copy and raw report disclosure.
- Change "Model attestations: N" to a coverage phrase: `1 of 1 models verified` or `GLM verified via TEE`.
- Add share/export verification affordance once signed export and verifier are exposed in product.

## Work Packets

### Packet D0: Product Visual Foundation

Build:
- Keep SF Pro only.
- Define semantic color roles for action, trust, warning, destructive, surface, panel, border, and secondary text.
- Keep current app tokens where useful; add aliases if that makes implementation easier.
- Add accessibility contrast checks for metadata, chips, and buttons.

Acceptance:
- No new custom font dependency.
- Main screens keep readable hierarchy at Dynamic Type sizes.
- Weak grey text is darkened where needed.

### Packet D1: Optional Trust Icon Asset

Build:
- Review the PDF for the Private Chat/shield/chat-bubble icon idea only.
- If useful, recreate or extract a clean vector asset.
- Add monochrome/tintable variants.
- Use only on attestation/trust surfaces.

Acceptance:
- Icon renders clearly at 16pt and 20pt.
- SF Symbol fallback remains available.
- No palette/type/layout decisions are inherited from the PDF.

### Packet D2: Attestation Visibility

Build:
- Add compact chat-header shield.
- Use trust-state grammar for fresh/recent/stale/mismatch/unavailable.
- Keep per-message chips.
- Add model picker badge, export header, verifier mark, and share-preview seal.

Acceptance:
- Attestation is visible before opening overflow.
- All shield taps open Security.
- States are distinguishable by icon, text, and color.

### Packet D3: Home Information Diet

Build:
- Remove/demote toolbar plus.
- Make Ask the sole primary CTA.
- Gate Agent/Context based on setup intent or active context.
- Separate system collections from projects.
- Add project icon/color.

Acceptance:
- First screen has no more than 8 major visible concepts.
- New user path to first prompt is obvious.

### Packet D4: Project Taxonomy And Identity

Build:
- Rename tabs/copy to `Sources / Files / Instructions / Notes`.
- Update tests and docs for renamed concepts.
- Add project icon/color picker and row preview.
- Hide zero metadata everywhere.

Acceptance:
- No user-facing `Library`, `Guide`, or `Saved` labels remain for project tabs.
- Project rows scan visually without comma-separated metadata.

### Packet D5: Share Safety Design

Build:
- Add public-link preview and confirm.
- Add expiry control.
- Add invite-first secondary button.
- Add attestation seal.
- Add undo/confirmation for disable/revoke.

Acceptance:
- No public publishing action completes without a preview or confirm step.
- User can understand exactly what becomes public.

### Packet D6: Account And Settings Hygiene

Build:
- Regroup settings into Composer, Privacy, Models, Integrations, Developer.
- Keep advanced params, endpoints, callbacks, keys, and IronClaw bridge inside Developer/Integrations.
- Reduce helper paragraphs.

Acceptance:
- Account can be scanned in one pass by a non-developer.
- Developer setup remains reachable but not dominant.

### Packet D7: Motion And Accessibility Pass

Build:
- Add restrained spring transitions for focus chip, tab selection, send activation, and attestation state changes.
- Respect Reduce Motion.
- Audit contrast against WCAG AA for metadata and chips.
- Dynamic Type pass for home, composer, model picker, Project Context, Account.

Acceptance:
- No clipped text at accessibility sizes.
- Small grey metadata meets contrast targets or is darkened.

## Definition Of Done

- SF Pro is used throughout the product UI.
- No FK Grotesk dependency is added.
- Brand guidelines are not treated as binding for type, color, layout, gradient, spacing, or tone.
- Optional custom iconography is used only if it improves trust/verification clarity over SF Symbols.
- Compact chat header shows attestation freshness/state.
- Public link creation has preview/confirm and expiry.
- Home has one primary Ask path and no duplicate primary new-chat control.
- Project vocabulary is reduced to Sources, Files, Instructions, Notes.
- Color roles are semantic: action, trust, warning, destructive, surface, text.
- Accessibility pass covers contrast, Dynamic Type, Reduce Motion, and icon-only buttons.

## Bottom Line

The brand guidelines should not drive the product. SF Pro is the right call. Use native iOS patterns, clear hierarchy, and strong trust surfaces. If the PDF has a useful shield/chat icon, bring that idea in carefully as optional iconography; leave the rest behind.

