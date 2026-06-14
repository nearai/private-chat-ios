# Home Streams Polish Notes

Date: 2026-06-12

## Goal

Move the default Home feed closer to the supplied Streams reference: editorial stream cards, clear type/status metadata, visible recovery affordance, and less flat/anonymous chat history.

## What Changed

`NEARPrivateChat/Features/Home/HomeInboxSection.swift`

- `HomeRecentCard` now renders with a typed accent rail, larger tinted icon, uppercase metadata, stronger title hierarchy, footer chips, and a clearer open affordance.
- Failed/private-route-limited cards get a warm warning treatment and an `Open thread` chip instead of looking like a normal chat preview.
- Conversation cards infer only safe visible categories from title/preview:
  - `Answer`
  - `Council`
  - `Briefing`
  - `Research`
- The card does not invent hidden sources; topic chips are broad visible-context hints only.

## Evidence

Build/install/launch succeeded on iPhone 17 Pro simulator.

Screenshot:

- `review-artifacts/screenshots/2026-06-12-home-streams-polish/home-stream-cards-after.jpg`

## Remaining Product Gaps

- This is a visual/feed-card pass only; it does not complete the broader goal.
- Still needed:
  - Answer thread and briefing detail visual parity against the supplied references.
  - Generative-widget workflow hostile tests across recurring price trackers, release monitors, daily digests, schedules, and saved briefings.
  - Backend/private-route reliability confirmation after AASA and OVH/private-route fixes.
