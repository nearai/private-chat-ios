# Private Route Rate-Limit / Session Retention Sidecar Issue

Date: 2026-06-12
Sidecar agent: `019ebce9-e3d3-7002-b718-20d5b172f1b1`
Repo: `/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS`
GitHub issue: https://github.com/abbyshekit/NEARPrivateChatIOS/issues/12

## Symptom

Private-route prompts intermittently fail with copy like:

- `Private route is rate-limited for this session. Retry private; if it keeps failing, sign out and back in. Use the privacy proxy only for this turn.`
- `The private route is temporarily busy...`
- Earlier hostile-run evidence also captured `Failed to check rate limit.`

This shows up after sign-in and blocks real current-news/live-search testing. The user suspects the app is not retaining session identity, or that inference is being bucketed as a new or anonymous session. Another explanation offered was that rate limiting is managed through OVH/private-route infrastructure.

## Related AASA / Auth Callback Finding

The attached PDF `/Users/abhishekvaidyanathan/Downloads/private-near-ai-change-1-aasa.pdf` says `https://private.near.ai/.well-known/apple-app-site-association` must return AASA JSON for the Universal Link callback `https://private.near.ai/auth/callback`.

Live check on 2026-06-12:

```sh
curl -i https://private.near.ai/.well-known/apple-app-site-association
```

Current result: `HTTP/2 200`, but `content-type: text/html`, and the body is the SPA `index.html`.

This is not fixable from Xcode, TestFlight, or iOS code. It must be fixed in the `private.near.ai` server/CDN/gateway/static deployment before the frontend catch-all route. Without it, Universal Link auth can be unreliable and the app may fall back to WKWebView/localStorage harvesting.

Important distinction: AASA can explain auth callback/session handoff failures. It does not by itself explain inference-time rate limiting after the app already has a valid session token.

## Current iOS Behavior Observed In Code

- `SessionStore.adoptSession(token:sessionID:isNewUser:)` persists the token/session via `SessionPersistence.saveSession` and sets `api.authToken`.
- `APIClient.makeRequest(... authenticated: true)` sends both:
  - `Authorization: Bearer <session token>`
  - `Cookie: nearai-prod_crabshack_session=<session token>`
- `ChatStore.probePrivateSession()` calls `/v1/users/me` and records raw diagnostics.
- `/v1/responses` streaming uses the same authenticated `APIClient.makeRequest`.
- `RouteHealthMonitor.isTransientBusyFailure` currently treats rate-limit messages as transient.
- `ChatStore.streamResponseWithFallback` immediately retries one private request on `isTransientBusyFailure` before recording the failure and opening the breaker.

That last behavior is a likely client-side contributor: if the backend/OVH limiter is strict per session, immediate same-route retry can burn quota or extend the restriction window.

## Ranked Hypotheses

1. **Backend/OVH inference limiter is rejecting the authenticated session.**
   Evidence: wording says `rate-limited for this session`; app sends auth headers; `/v1/users/me` can be valid while inference is separately limited.

2. **AASA/auth callback is not fully deployed, causing some sign-ins to produce no app session or require fragile web storage harvesting.**
   Evidence: live AASA endpoint returns HTML, not JSON. This must be fixed server-side.

3. **iOS retry behavior amplifies rate limits.**
   Evidence: `streamResponseWithFallback` retries once immediately for rate-limit-class failures before tripping the breaker.

4. **Missing diagnostic metadata prevents us from distinguishing lost auth from OVH quota.**
   Evidence: `APIError.status` only carries status/message, not response headers like `Retry-After`, request ID, or rate-limit bucket.

5. **Session token is valid for profile APIs but not accepted by private inference.**
   Evidence: `probePrivateSession()` only checks `/v1/users/me`; it does not prove `/v1/responses` private inference accepts the same session.

## iOS Fix Candidates

1. Split `rate-limit` from `temporarily busy`.
   - Do not do the one immediate same-route retry for explicit rate-limit / temporarily restricted / too many requests.
   - Keep a one-time retry only for actual transient busy/server overload signals where the backend asks to retry.
   - Files: `NEARPrivateChat/Core/Routing/RouteHealthMonitor.swift`, `NEARPrivateChat/App/State/ChatStore+StreamingRuntime.swift`.

2. Preserve and surface response headers.
   - Extend API errors/diagnostics to capture `Retry-After`, `x-request-id`, rate-limit headers, and route error code if present.
   - Show this in `ConnectionDiagnosticsView` and allow copy/share of diagnostics with secrets redacted.
   - Files: `NEARPrivateChat/Core/API/APIClient.swift`, `NEARPrivateChat/Core/Routing/ConnectionDiagnostics.swift`, `NEARPrivateChat/Features/Account/ConnectionDiagnosticsView.swift`.

3. Add an inference-specific private route health probe.
   - `/v1/users/me` only proves session auth, not route capacity.
   - If backend has or can add a cheap route-health endpoint, call it after login and when private route fails.
   - If no endpoint exists, ask backend for one rather than sending a real model prompt as a probe.

4. Improve failed-turn recovery UI.
   - When diagnostics say session-rate-limited, the primary action should be `Check private route` / `Use Cloud once`, not repeated `Retry private`.
   - Manual `Retry private` should respect cooldown and `Retry-After` when available.
   - Files: `NEARPrivateChat/Features/Chat/ChatMessageViews.swift`, `NEARPrivateChat/App/State/ChatStore+SendActions.swift`.

5. Add regression tests.
   - Explicit rate-limit errors must not trigger immediate private retry.
   - Auth failures must remain distinct from rate limits.
   - Rate-limit diagnostics must preserve raw status/message and available retry metadata.
   - Signing in/adopting a session must persist token + session ID and retain them across app relaunch.

## Backend / Infra Ask

If OVH/private-route infrastructure owns the limiter, iOS still needs these backend guarantees:

1. Fix AASA route:
   - `/.well-known/apple-app-site-association`
   - `200`, `application/json`, no redirect, no auth/cookies, no SPA fallback.

2. Return machine-readable inference errors:
   - `error.code`: e.g. `private_route_rate_limited`, `private_route_capacity`, `session_invalid`, `quota_exceeded`
   - `retry_after_seconds`
   - `request_id`
   - `session_id_hash` or `rate_limit_bucket_hash` that cannot reveal the token but lets support correlate failures.

3. Confirm expected auth contract for `/v1/responses`:
   - Is `Authorization: Bearer <session token>` sufficient?
   - Is `nearai-prod_crabshack_session=<session token>` still the correct cookie?
   - Does inference use a different session, account, or OVH bucket than `/v1/users/me`?

4. Provide a cheap authenticated route-health endpoint:
   - Example: `GET /v1/private-route/health`
   - Should report whether the current session is authenticated, rate-limited, quota-exhausted, or capacity-blocked without spending model tokens.

## Answer To "Can We Fix This?"

Partly in iOS, fully only with backend/gateway cooperation.

We can fix the client-side amplification, diagnostics, retry UX, and auth/session persistence validation. We cannot fix an OVH/private-route quota bucket or the broken AASA response from the iOS repo alone. The immediate iOS patch should stop same-route retries on explicit rate limits, capture richer diagnostics, and gate retry UI behind real route state. The server-side patch must fix AASA and expose machine-readable route-limit/auth errors.
