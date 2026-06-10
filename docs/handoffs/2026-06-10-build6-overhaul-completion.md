# Build 6 — Comprehensive Overhaul Completion

Date: 2026-06-10
Plan: approved plan-mode design (reliability + rendering + projects redesign + live harness), driven by the Archive 4.zip TestFlight review (17 screenshots).

## What changed, by reported issue

| Your report | What ships in build 6 |
|---|---|
| Private models stall → "Access temporarily restricted" on ALL of them | `RouteHealthMonitor` circuit breaker: after a restricted-class failure the app stops hammering the route (60s→600s exponential cooldown), auto-fallback is capped at ONE hop (was walking the whole catalog), council legs on a tripped route fail instantly instead of burning 40s each, trackers back off 15m→6h instead of refiring on every app-open, follow-ups stop hardcoding GLM. **This also gives the server-side account restriction room to clear.** Failed private sends show a one-tap **"Answer via privacy proxy"** card (disclosed, single-turn, selected model unchanged); tracker threads get the same offer; composer shows a "Private busy" chip with tap-to-retry |
| Council synthesis fails with raw `NSURLError -1005` dump | Transport errors map to human copy app-wide ("Connection dropped mid-answer — retry. Your prompt is kept."); synthesis retries once automatically on transport drops, total prompt capped at 12k chars, routes to a healthy successful member (cloud legs immune to private restriction); "Synthesize again" works from the Room |
| Council answers disappear on re-open | Root cause: the merge dropped all local-only turns unless an external-model turn existed, then saved the stripped result over the cache. Per-message preservation now keeps council members, synthesis, failed/cancelled turns; council turns persist on success. Unit-pinned |
| Latency selecting council models | Cached lineup resolution + O(1) selection snapshot per row + deferred banner/route side effects per toggle |
| Sources don't render on private; icons broken; bars bleed | Carousel clipped + width-constrained (was `scrollClipDisabled` with 304pt cards), cards resized to fit 393pt with a peek; composer chips and the inline-actions row constrained the same way; favicon initials never render "#" (www/punycode fall back to title initials); source dialog states honestly that private may answer from model knowledge — a DEBUG SSE logger is in place so the first live gate run settles whether private emits web events under other names |
| Parts of responses unviewable (ellipsized bullets, clipped tables) | Bullets/numbered items wrap fully; ≤3-column tables fill the bubble and wrap completely; wider tables scroll AND tap-to-expand into a full-content sheet; permanent `markdownGallery` demo screen renders the exact failing corpus as a regression surface |
| Responses rendering in plaintext (raw `**`/`##`) | Council previews, room cards, and streaming bubbles render real markdown; in-flight text is sanitized (never raw markers) via `StreamingMarkdownText` |
| Must finish/cancel response before switching chats | Switching now auto-cancels: partial text persisted into its own chat, "Stopped — Regenerate" affordance, no blocking banner |
| Tracker doesn't work / dies silently | (Build-5 work, completed here) failed runs show reason + Run again; runs back off; follow-ups use the briefing's route with proxy fallback offer |
| Agent Instructions/Notes tabs unintuitive | Project home: **"Model sees"** summary bar + tap-through preview of exactly what attaches to sends; Chats promoted above Sources; Notes → "Saved answers"; instructions editor has one clear purpose per field; "No report" badge → "Get proof"; agent suggestions are concrete tasks built from the project's real files/links instead of the planning template |
| PDF text never reaches the model | Three real bugs fixed: share-extension files skipped extraction entirely; staged text was memory-only (app restart → filename-only, your exact screenshot); council prompts skipped document context. Now: share files extract, lost text re-fetches from the uploaded `…-pdf-text.txt`, council (all-private lineups) and hosted-agent prompts carry capped untrusted excerpts, and the composer shows "Reading term-sheet.pdf — text goes to the model" |

## Verification

- **518 unit tests green** (506 inherited + 12 new pinning breaker/backoff/merge/copy behavior), every stage committed only on a green suite.
- Demo-capture proof at iPhone width: `markdownGallery` (layout corpus), `chatFailure`, `trackerFailure`, `project` (new IA), `chat`.
- **ReleaseGate live harness** (`NEARPrivateChatUITests/ReleaseGateTests`) is built, registered, and dry-run verified: without a token all live scenarios SKIP with an actionable message and the offline layout gate PASSES against the real app.

## The two steps that need you

1. **Run the live gate against production** (this is the "beta-test so obvious errors don't manifest" step — I cannot mint your session):
   ```sh
   cd /Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS
   export NEAR_DEBUG_SESSION_TOKEN=<your session token>   # env-only, never written to disk
   export NEAR_DEBUG_CLOUD_KEY=<optional cloud key>
   scripts/release-gate.sh
   ```
   Per-scenario table + screenshots land in `build/ReleaseGate/`. R2 also settles the private-route web-events question (watch for `[MessageAPI] unrecognized SSE event type:` in the log); R6 proves PDF content reaches the model via the ZEPHYR-7 sentinel.
2. **Upload**: archive exists after the gate passes; the export/upload command (GUI Xcode session or ASC API key) is unchanged from `docs/handoffs/2026-06-09-testflight-hardening-completion.md` § Upload status.

## Deferred (tracked, deliberate)

- `MarkdownRenderingViews.swift` split into per-component files (RULES compliance; pure mechanical move, no user-facing impact).
- Per-conversation background streaming (auto-cancel shipped instead; the detached-completion architecture is a future phase).
- `supportsNativeWebTool` flip for private route — decided by the first live gate run's SSE evidence.
