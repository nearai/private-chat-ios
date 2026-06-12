# Private Route Reliability Runbook: iOS App vs OVH / Backend

Date: 2026-06-12
Repo: `/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS`
Related local note: `docs/handoffs/private-route-rate-limit-sidecar-issue-2026-06-12.md`
Related GitHub issue: `https://github.com/abbyshekit/NEARPrivateChatIOS/issues/12`
Attached infra reference: `/Users/abhishekvaidyanathan/Downloads/private-near-ai-change-1-aasa.pdf`

## Problem

The iOS app can sign in and then later hit private-route failures such as:

- `Private route is rate-limited for this session.`
- `The private route is temporarily busy.`
- `Missing authorization header`
- `Failed to check rate limit.`

The user-level symptom is worse than a normal model failure: the app appears signed in, but private GLM answers fail or get trapped behind retry/busy copy. The suspected causes are either session identity not being retained/sent consistently, or the OVH/private-route limiter rejecting the authenticated session independently from the profile API.

## Current iOS Contract

Authenticated private API requests are built through `APIClient.makeRequest(... authenticated: true)`.

The app sends:

- `Authorization: Bearer <session token>`
- `Cookie: nearai-prod_crabshack_session=<session token>`
- `Origin: https://private.near.ai`
- `Referer: https://private.near.ai/`

The `/v1/responses` stream uses that same authenticated request path. If these headers are present and the backend still returns rate-limit or missing-auth wording, the next debugging step is backend/gateway logs, not more UI guesswork.

## What iOS Can Fix

These are app-owned and should be guarded by unit tests:

1. Normalize and validate stored sessions before reuse.
   - Trim token and session ID before setting `api.authToken`.
   - Reject whitespace-only stored tokens.
   - Respect `expires_at` when present so a stale local token is not treated as signed in.

2. Keep auth failure distinct from rate limiting.
   - `401`, missing bearer/header, invalid token, expired token, missing session token, and token rejected must route to sign-in recovery copy.
   - Explicit rate-limit signals should route to cooldown/rate-limit copy.
   - Generic busy/capacity signals can allow a bounded retry; explicit rate limits should not be retried immediately.

3. Prevent retry amplification.
   - Do not send an immediate second private `/v1/responses` request when the server says the session is rate-limited.
   - Keep one same-route retry only for genuine transient busy/capacity wording.

4. Preserve raw diagnostics.
   - Diagnostics should record status, raw backend message, route, model, and auth-vs-rate-limit classification.
   - Future improvement: carry `Retry-After`, request ID, and rate-limit headers through the API error layer once backend returns them.

5. Reset local route state on credential change.
   - Signing in with a fresh session should clear private route breaker state and stale diagnostics.

## What iOS Cannot Fix

iOS cannot fix these from Xcode or TestFlight:

1. OVH/private-route capacity or quota buckets.
   - If the limiter rejects a valid session, only backend/infra can change bucket policy, capacity, or rate limits.

2. Broken Universal Link AASA serving.
   - `https://private.near.ai/.well-known/apple-app-site-association` must return AASA JSON.
   - It must not return the SPA HTML shell.
   - It must be served with no auth, no redirect, and preferably `application/json`.

3. Missing machine-readable private-route errors.
   - If backend only returns prose, iOS can classify common strings, but support cannot reliably tell capacity from quota from stale auth.

## Backend / OVH Required Changes

### 1. Serve AASA Before SPA Fallback

The route below must bypass the app shell:

```text
GET /.well-known/apple-app-site-association
```

Expected response:

```http
HTTP/2 200
Content-Type: application/json
Cache-Control: public, max-age=300
```

The body must include the app ID for the TestFlight bundle, including the Apple Team ID:

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appIDs": ["RYJ2LB9649.ai.near.privatechat.ios"],
        "components": [
          {
            "/": "/auth/callback",
            "comment": "NEAR Private Chat iOS auth callback"
          }
        ]
      }
    ]
  }
}
```

Verify from a clean network:

```sh
curl -i https://private.near.ai/.well-known/apple-app-site-association
```

Do not accept:

- `text/html`
- redirect to `/`
- SPA `index.html`
- `401` / `403`
- content that requires cookies

### 2. Confirm Private Inference Auth Contract

Backend owner should confirm, in writing, what `/v1/responses` expects:

- Is `Authorization: Bearer <private.near.ai session token>` sufficient?
- Is `nearai-prod_crabshack_session=<same token>` still required?
- Is the session token from hosted web login valid for inference, not just `/v1/users/me`?
- Does inference use a different account/session bucket than profile and conversation APIs?
- Can the backend log and compare a request ID from a failing `/v1/responses` call?

### 3. Add Machine-Readable Error Bodies

Return structured JSON for private-route failures:

```json
{
  "error": {
    "code": "private_route_rate_limited",
    "message": "Private route is rate-limited for this session.",
    "retry_after_seconds": 120,
    "request_id": "req_...",
    "route": "near_private",
    "model": "zai-org/GLM-5.1-FP8"
  }
}
```

Recommended codes:

- `session_missing`
- `session_invalid`
- `session_expired`
- `private_route_rate_limited`
- `private_route_capacity`
- `quota_exceeded`
- `rate_limit_check_failed`

Recommended headers:

- `Retry-After`
- `X-Request-ID`
- `X-RateLimit-Limit`
- `X-RateLimit-Remaining`
- `X-RateLimit-Reset`

Do not include the raw session token in any log, response body, or diagnostic.

### 4. Add A Cheap Private Route Health Endpoint

Add an authenticated route that does not spend model tokens:

```text
GET /v1/private-route/health
```

Expected successful response:

```json
{
  "authenticated": true,
  "route": "near_private",
  "available": true,
  "limited": false,
  "retry_after_seconds": null,
  "request_id": "req_..."
}
```

Expected limited response:

```json
{
  "authenticated": true,
  "route": "near_private",
  "available": false,
  "limited": true,
  "reason": "private_route_rate_limited",
  "retry_after_seconds": 120,
  "request_id": "req_..."
}
```

iOS should use this after sign-in and after private-route failures. Until this endpoint exists, `/v1/users/me` only proves account auth; it does not prove inference availability.

## App-Side Status

Patched in this pass:

- `NEARPrivateChat/Core/Auth/SessionStore.swift`
  - Stored sessions are normalized before reuse.
  - Whitespace-only and expired sessions are rejected before setting `api.authToken`.
  - Adopted sessions preserve `expiresAt` when the caller has it.

- `NEARPrivateChat/Features/Auth/WebSignInView.swift` and `NEARPrivateChat/Features/Auth/AuthView.swift`
  - Hosted web sign-in now passes the full `AuthSession` back to `SessionStore`, instead of dropping `expiresAt` at the sheet boundary.

Already present and now guarded by focused tests:

- `NEARPrivateChat/Core/Routing/RouteHealthMonitor.swift`
  - Auth classification now catches missing bearer, missing token, invalid token, expired token, missing session token, and token rejected wording.

- `NEARPrivateChat/Core/API/ErrorMessageMapper.swift`
  - User-facing failure copy maps those token/header failures to sign-in recovery instead of busy/rate-limit language.

Focused tests added under:

  - `NEARPrivateChatTests/Auth/AuthTests.swift`
  - `NEARPrivateChatTests/Routing/RouteHealthTests.swift`

## Validation Checklist

iOS:

```sh
scripts/build-simulator.sh
```

Focused XCTest targets to run:

- `testSessionStoreNormalizesUsableSessionBeforeReuse`
- `testSessionStoreRejectsWhitespaceOrExpiredSessionBeforeReuse`
- `testAuthFailureIsDistinguishedFromRateLimit`
- `testDisplayFailureMessageMapsRejectedSessionToAuthRecovery`
- Existing private-route retry tests in `RouteHealthTests` and streaming tests.

Validation run from this patch:

- Focused XCTest: passed 4/4
  - `testSessionStoreNormalizesUsableSessionBeforeReuse`
  - `testSessionStoreRejectsWhitespaceOrExpiredSessionBeforeReuse`
  - `testAuthFailureIsDistinguishedFromRateLimit`
  - `testDisplayFailureMessageMapsRejectedSessionToAuthRecovery`
  - Result bundle: `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T20-04-47-982Z_pid55401_b9d19dbb.xcresult`

- Simulator build/install/launch: passed
  - App: `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/DerivedData/NEARPrivateChat-9a65868f573e/Build/Products/Debug-iphonesimulator/NEARPrivateChat.app`
  - Build log: `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T20-07-12-713Z_pid55401_cc856137.log`

Infra:

```sh
curl -i https://private.near.ai/.well-known/apple-app-site-association
curl -i -H "Authorization: Bearer <redacted>" https://private.near.ai/v1/users/me
curl -i -H "Authorization: Bearer <redacted>" https://private.near.ai/v1/private-route/health
```

Never paste real tokens into tickets, docs, screenshots, or PR descriptions.

## Bottom Line

The app can reduce self-inflicted failures and make diagnostics honest. It cannot repair an OVH/private-route limiter or a wrongly served AASA file. The durable fix needs both sides:

1. iOS rejects stale local sessions, avoids retry amplification, and records honest diagnostics.
2. Backend/OVH serves AASA correctly, confirms the inference auth contract, returns structured rate-limit/auth errors, and provides a cheap route health endpoint.
