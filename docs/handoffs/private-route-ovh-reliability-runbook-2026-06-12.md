# Private Route OVH Reliability Runbook

Date: 2026-06-12
App repo: `NEARPrivateChatIOS`
Related issue: https://github.com/abbyshekit/NEARPrivateChatIOS/issues/12
Related AASA PDF: `/Users/abhishekvaidyanathan/Downloads/private-near-ai-change-1-aasa.pdf`

## Problem

The iOS app can authenticate and then still see private-route failures such as:

- `Private route is rate-limited for this session.`
- `The private route is busy right now.`
- `Access temporarily restricted. Please try again later.`
- `Failed to check rate limit.`
- `Missing authorization header.`

These are not all the same class of failure. Treating them as one bucket makes the product feel broken and sends the user toward the wrong recovery path.

## What iOS Can Fix

1. Preserve session credentials and send them consistently.
   - `APIClient.makeRequest(... authenticated: true)` should send both:
     - `Authorization: Bearer <session token>`
     - `Cookie: nearai-prod_crabshack_session=<session token>`
   - `SessionStore.adoptSession(token:sessionID:isNewUser:)` should persist the session and set `api.authToken`.

2. Distinguish explicit rate limits from transient capacity.
   - Explicit rate-limit signals: HTTP `429`, `too many requests`, `rate limit`, `rate-limited`, `temporarily restricted`.
   - Busy/capacity signals: `private route is busy`, `temporarily busy`.
   - The app should not immediately retry the same private route after an explicit rate limit because that can amplify the OVH/session bucket.
   - A single short retry is acceptable only for true busy/capacity messages.

3. Keep auth failures separate from rate limits.
   - Auth failures: `401`, `missing authorization header`, `invalid session`, `expired session`, `not authenticated`.
   - These should tell the user to sign in again, not to wait.

4. Surface honest recovery actions.
   - Auth failure: sign out/in, then retry.
   - Explicit private-route rate limit: wait for cooldown, or use Cloud/proxy for this turn.
   - Busy/capacity: retry in a moment, or use Cloud/proxy for this turn.

5. Improve diagnostics.
   - Preserve raw HTTP status and message.
   - If backend provides them, capture `Retry-After`, `x-request-id`, `x-rate-limit-*`, route error code, and correlation ID.
   - Never log or export the raw session token.

## What OVH / Backend Must Fix

### 1. Serve AASA JSON From `private.near.ai`

The app needs Universal Links for:

```text
https://private.near.ai/auth/callback
```

Current check on 2026-06-12:

```sh
curl -i https://private.near.ai/.well-known/apple-app-site-association
```

Observed response:

```text
HTTP/2 200
content-type: text/html
```

Body starts with the SPA `<!doctype html>`. That means the request is falling through to the frontend catch-all route. iOS cannot fix this. The gateway/CDN/static server must serve AASA before the SPA fallback.

Expected response:

```text
HTTP/2 200
content-type: application/json
```

No redirect, no auth, no cookies required, no `.json` extension.

Minimum payload shape:

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
            "comment": "NEAR Private Chat mobile auth callback"
          }
        ]
      }
    ]
  }
}
```

Verify with:

```sh
curl -i https://private.near.ai/.well-known/apple-app-site-association
xcrun simctl openurl booted "https://private.near.ai/auth/callback?state=test"
```

### 2. Return Machine-Readable Private Route Errors

The app needs to stop inferring backend state from prose strings. Add stable fields to private inference failures:

```json
{
  "error": {
    "code": "private_route_rate_limited",
    "message": "Access temporarily restricted. Please try again later.",
    "retry_after_seconds": 120,
    "request_id": "req_...",
    "session_bucket_hash": "sha256:..."
  }
}
```

Suggested `error.code` values:

- `session_missing`
- `session_invalid`
- `session_expired`
- `private_route_rate_limited`
- `private_route_capacity`
- `quota_exceeded`
- `model_unavailable`
- `rate_limit_check_failed`

The app should never receive `Missing authorization header` if the request arrived with an `Authorization` header. If that still happens, backend/gateway logs need to show where the header was stripped.

### 3. Confirm The Inference Auth Contract

Backend/infra owner should answer these exactly:

- Is `Authorization: Bearer <session token>` sufficient for `/v1/responses`?
- Is `Cookie: nearai-prod_crabshack_session=<session token>` still required?
- Does OVH strip or normalize either header?
- Does `/v1/users/me` use the same session validator as `/v1/responses`?
- Is inference rate-limited by session token, account ID, IP, route, model, or a combined bucket?
- What is the intended cooldown, and is `Retry-After` available?

### 4. Add A Cheap Authenticated Route Health Endpoint

Do not make iOS spend a real model prompt to test route health.

Suggested endpoint:

```text
GET /v1/private-route/health
Authorization: Bearer <session token>
Cookie: nearai-prod_crabshack_session=<session token>
```

Suggested response:

```json
{
  "authenticated": true,
  "inference_available": false,
  "status": "rate_limited",
  "retry_after_seconds": 93,
  "request_id": "req_...",
  "session_bucket_hash": "sha256:..."
}
```

## OVH / Gateway Checklist

1. Add a static/gateway rule for `/.well-known/apple-app-site-association` before SPA fallback.
2. Ensure `Authorization`, `Cookie`, `Origin`, and `Referer` survive proxy hops to the API service.
3. Ensure CORS allows the actual mobile/web origins that are intended:
   - `https://private.near.ai`
   - Any explicitly approved app callback origin.
4. Ensure the API service logs request ID, account/session bucket hash, model, route, and limit reason.
5. Add or expose `Retry-After` on `429` / explicit rate-limit responses.
6. Add machine-readable JSON error codes.
7. Add `/v1/private-route/health` or equivalent.
8. Confirm the rate-limit bucket and cooldown with iOS so UI copy and retry cooldown match backend truth.

## iOS Validation Checklist

1. Fresh install.
2. Sign in through hosted web flow.
3. Verify persisted session after app relaunch.
4. Run `probePrivateSession()` and confirm `/v1/users/me` succeeds.
5. Send a private GLM 5.1 prompt.
6. Force/mock `401 Missing authorization header`; app must show sign-in recovery.
7. Force/mock explicit `429` or `Access temporarily restricted`; app must not immediately same-route retry.
8. Force/mock `private route is busy`; app may retry once after a short delay.
9. Confirm diagnostics show raw status/message but redact tokens.
10. Confirm Cloud/proxy fallback remains an explicit user choice, not a silent route switch.

## Current App-Side Fix In This Pass

The display error mapper now keeps private-route busy/capacity copy separate from explicit rate-limit copy:

- Busy: `Private route is busy right now. Retry private in a moment, or use the privacy proxy only for this turn.`
- Rate limit: `Private route is rate-limited for this session. Retry private; if it keeps failing, sign out and back in. Use the privacy proxy only for this turn.`

Regression coverage:

- `testDisplayFailureMessageDistinguishesPrivateBusyFromRateLimit`

## Bottom Line

Can we fix this entirely in iOS? No.

iOS can stop amplifying rate limits, preserve and verify sessions, make retry behavior honest, and expose diagnostics. But if OVH/backend is stripping headers, serving AASA as HTML, enforcing a bad session bucket, or returning prose-only rate-limit errors, that has to be fixed at the gateway/API layer.
