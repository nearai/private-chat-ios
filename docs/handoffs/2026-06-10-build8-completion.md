# Build 8 — Auth honesty + diagnostics (2026-06-10)

Commit `e740a54`, archive `build/Archives/NEARPrivateChat-20260610-b8-unsigned.xcarchive` (** ARCHIVE SUCCEEDED **, log `/tmp/npc-archive-b8.log`). Full unit suite green.

## What this build answers

Builds 5–7 kept failing the same way: the app translated every private-route failure into "temporarily busy," so a broken session looked identical to a rate limit and no fix could be verified. Build 8 stops translating.

### Auth honesty
- `ConnectionDiagnostics` (Core/Routing) records the real HTTP status + server body of the last request per route. New **Connection Diagnostics** screen in Capabilities shows them verbatim (selectable text), with a "Run private probe now" button (`/v1/users/me` with the stored session token) and a warning banner when the private route returned an auth failure while Cloud worked.
- A post-login probe runs concurrently with bootstrap, so a wallet login that doesn't yield a valid private.near.ai session surfaces at sign-in.
- `RouteHealthMonitor` now classifies auth failures (`isAuthFailure`): 401s and auth-worded 403s trip only the private breaker and the notice says *sign out and sign back in* instead of *temporarily busy*. A rate-limit 403 still says busy. Cloud/agent 401s (missing key — thrown locally) never trip their routes.

### Client fixes from the build-7 feedback list
- **Council**: explicit lineups are honored exactly; the selected model (GLM) is no longer force-prepended, so an all-cloud 3-model council keeps all three picks.
- **Trackers / privacy proxy**: cloud and proxy model IDs route through the Cloud completion API with headless web grounding (they previously hit the private streamer and died). Cloud runs and proxy follow-ups no longer require creating a private conversation, so they work when the private session is the thing that's broken.
- **PDF/XLS extraction**: when a generic question ("summarize this") shares no keywords with the document, the chunker now inlines opening chunks — round-robin across attachments so multi-doc asks hear from every file — instead of silently sending only the filename.
- **Web search**: low-signal follow-ups ("try again") reuse the last substantive query instead of being searched literally; prompts sent on the private route are never shipped to search engines as substitute queries.
- **Source icons**: real favicons, fetched through a cookie-free ephemeral session with an in-memory cache, shown only for sources that came from an explicit web search. Model-emitted widget domains render the local tinted-letter tile — conversation-derived hostnames never leave the device.

## Review gate

Adversarial workflow (4 dimensions × finder → independent refuter, 26 agents): 22 raw findings, 21 confirmed, all fixed in this build. Notables beyond the list above: the agent pipeline's re-wrapped restriction notice now classifies as auth (no re-laundering on the Agent route); diagnostics ignores user cancellations; the "while Cloud worked" banner clause only appears when Cloud actually succeeded.

## What this build cannot prove from the simulator

Whether the wallet session token is actually valid for private.near.ai. That's the point of the diagnostics screen: on device, open **Capabilities → Connection diagnostics → Run private probe now**. The screen shows the exact status + server message. If it's 401/403 with auth wording, the session never authenticated and the fix is server-side/login-flow, not client copy.

## Upload (needs GUI Xcode or ASC key — same as builds 5–7)

```sh
cd /Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS
xcodebuild -exportArchive \
  -archivePath "$PWD/build/Archives/NEARPrivateChat-20260610-b8-unsigned.xcarchive" \
  -exportPath "$PWD/build/ExportBuild8" \
  -exportOptionsPlist "$PWD/build/ExportOptions-b5.plist" \
  -allowProvisioningUpdates
```

Open Xcode once first so the ASC account session is live, or drop an ASC API key at `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` and add `-authenticationKeyID <KEYID> -authenticationKeyIssuerID <ISSUER>` for a fully headless upload.

## Out of scope (flagged, not addressed)

- "Most recent ironclaw reborn not wired in properly" — the agent-route runtime wasn't part of the agreed build-8 scope; needs its own investigation.
- Search-source diversity beyond Google News: the DuckDuckGo backend already runs in parallel; if results still skew to news.google.com on device, the ranking weights are the next lever.
