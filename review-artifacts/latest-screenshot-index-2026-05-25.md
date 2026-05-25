# Latest Screenshot Index - 2026-05-25

Purpose: record the screenshot sources checked for the latest design pass.

## Primary Live App Capture

Use this pack first. It was captured from the actual app running in Simulator on 2026-05-25 after a successful Xcode build/install/launch:

`/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS/review-artifacts/live-app-review-2026-05-25/`

- `00-live-setup.png`
- `01-live-new-chat-after-skip.png`
- `02-live-model-picker.png`
- `03-live-model-picker-council.png`
- `04-live-more-menu.png`
- `05-live-security-no-proof.png`
- `06-live-home.png`
- `07-live-account-top.png`
- `08-live-model-search-cloud.png`
- `09-live-cloud-council-selected.png`
- `10-live-model-search-ironclaw.png`
- `11-live-hosted-ironclaw-selected.png`
- `12-live-more-menu-agent-visible.png`
- `13-live-connect-agent.png`
- `14-live-home-ironclaw-mode.png`
- `15-live-new-project-sheet.png`
- `16-live-project-context.png`

Controlling review:

`/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS/review-artifacts/NEARPrivateChatIOS-live-app-review-next-pass-2026-05-25.md`

## Other Captures Checked

1. `/Users/abhishekvaidyanathan/Desktop/Screenshot 2026-05-25 at 10.10.06 am.png`
   Timestamp: 2026-05-25 10:10:11
   Notes: latest desktop capture checked. Shows the simulator home screen with the installed `Private Chat` app icon; not an in-app product screen.

2. `/Users/abhishekvaidyanathan/Desktop/Screenshot 2026-05-25 at 8.38.12 am.png`
   Timestamp: 2026-05-25 08:38:17
   Notes: latest user-provided screenshot. Shows the `Ready on day one` setup preview card typography problem.

3. `review-artifacts/latest-smoke/iphone17pro-2026-05-25-after-setup-card-font-fix.png`
   Timestamp: 2026-05-25 08:49:35
   Notes: fresh simulator screenshot after the setup preview typography patch. Captures the top of setup; the preview card is below the visible fold.

4. `review-artifacts/latest-smoke/iphone17pro-2026-05-25-setup-polish-booted.png`
   Timestamp: 2026-05-25 07:43:50
   Notes: latest pre-fix simulator setup screenshot in artifacts.

5. `review-artifacts/latest-smoke/iphone17pro-2026-05-25-setup-polish.png`
   Timestamp: 2026-05-25 07:43:21

6. `review-artifacts/latest-smoke/iphone17pro-2026-05-25-post-four-docs.png`
   Timestamp: 2026-05-25 07:37:41

7. `review-artifacts/latest-smoke/iphone17pro-current.png`
   Timestamp: 2026-05-25 07:21:21

## Older Full Screen Set

This pack is historical reference only. It is no longer the controlling source for design decisions because the live app review above shows materially newer Home, Composer, Model Picker, More Menu, Account, IronClaw, and Project Context states.

- `review-artifacts/screenshots-2026-05-24-fresh/00-setup.png`
- `review-artifacts/screenshots-2026-05-24-fresh/01-home.png`
- `review-artifacts/screenshots-2026-05-24-fresh/01b-home-project-selected.png`
- `review-artifacts/screenshots-2026-05-24-fresh/02-new-chat-composer.png`
- `review-artifacts/screenshots-2026-05-24-fresh/03-model-picker.png`
- `review-artifacts/screenshots-2026-05-24-fresh/04-model-picker-council.png`
- `review-artifacts/screenshots-2026-05-24-fresh/05-agent-workspace.png`
- `review-artifacts/screenshots-2026-05-24-fresh/06-new-project-sheet.png`
- `review-artifacts/screenshots-2026-05-24-fresh/07-project-context.png`
- `review-artifacts/screenshots-2026-05-24-fresh/08-project-library.png`
- `review-artifacts/screenshots-2026-05-24-fresh/09-account-settings.png`

## Remaining Gap

Before shipping the design push, generate a fresh post-push live set against the current build:

- setup top
- setup `Ready on day one`
- home
- home with project selected
- home with IronClaw selected
- new chat composer
- chat thread with proof shield
- model picker
- council picker
- Cloud search result
- Cloud selected / missing-key state
- IronClaw search result
- Hosted IronClaw missing-workstation state
- project context
- security
- connect agent / agent workspace
- share
- account/settings
- capabilities / Cloud + IronClaw connection states

Save the post-push pack under:

`/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS/review-artifacts/live-app-review-2026-05-25-post-design-push/`

The live review also found state bugs that need verification screenshots after implementation:

- Setup readiness copy must match the CTA and selected mode.
- Cloud single-model selection must not silently become Council.
- Hosted IronClaw must not show Mobile-agent empty-state copy.
- Proof chips must not truncate to ambiguous text like `No model`.
