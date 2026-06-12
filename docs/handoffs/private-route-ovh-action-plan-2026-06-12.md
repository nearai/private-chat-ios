# Private Route OVH Action Plan

Date: 2026-06-12
Repo: `/Users/abhishekvaidyanathan/Documents/Playground/NEARPrivateChatIOS`
Issue: https://github.com/abbyshekit/NEARPrivateChatIOS/issues/12

## Goal

Make the NEAR Private route reliable enough for TestFlight users to sign in, send GLM 5.1 private prompts, and recover honestly when OVH/backend capacity or session limits block inference.

The iOS app can reduce self-inflicted failures and show better diagnostics. It cannot repair gateway header stripping, OVH limiter policy, or the `private.near.ai` AASA route from the iOS repo.

## Current User Symptoms

- Sign-in can succeed, then private inference returns `Missing authorization header`.
- Private GLM prompts can fail with `Private route is rate-limited for this session`.
- Other failures appear as `The private route is temporarily busy` or `Failed to check rate limit`.
- `/v1/users/me` can succeed while `/v1/responses` still fails, which means profile auth is not enough evidence that inference is usable.

## iOS App Status

Already fixed on the iOS side:

- Session tokens are trimmed before persistence and before authenticated requests.
- Expired stored sessions are rejected when `expiresAt` is present.
- Auth failures are classified separately from rate limits.
- Explicit rate-limit failures no longer trigger an immediate second private `/v1/responses` request.
- Credential changes reset local private-route breaker and stale diagnostics.

Added in this pass:

- Structured SSE error events preserve their original status code instead of always becoming `HTTP 403`.
- `private_route_rate_limited` maps to `429`.
- `private_route_capacity` / busy / unavailable codes map to `503`.
- `503` private-route failures are eligible for the one bounded busy retry; `429` remains no-immediate-retry.

## Backend / OVH Required Work

### 1. Fix AASA Serving Before SPA Fallback

`private.near.ai` must serve Universal Links from the well-known path:

```sh
curl -i https://private.near.ai/.well-known/apple-app-site-association
```

Expected:

```text
HTTP/2 200
content-type: application/json
```

Not acceptable:

- `text/html`
- SPA `index.html`
- redirect to `/`
- auth-required response
- cookie-required response

Minimum body:

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

OVH/gateway rule: serve this static JSON before the frontend catch-all route.

### 2. Confirm Inference Auth Contract

Backend owner must confirm the exact `/v1/responses` auth contract:

- Is `Authorization: Bearer <private.near.ai session token>` sufficient?
- Is `Cookie: nearai-prod_crabshack_session=<same token>` required?
- Does OVH strip, rename, or normalize either header?
- Does `/v1/users/me` use the same validator as `/v1/responses`?
- Is inference limited by session token, account ID, IP, route, model, or a combined bucket?

If `Missing authorization header` appears when the iOS app sent `Authorization`, backend/gateway logs must identify the hop that dropped it.

### 3. Return Machine-Readable Route Errors

Do not force iOS to infer infrastructure state from prose. Return stable fields:

```json
{
  "error": {
    "code": "private_route_rate_limited",
    "message": "Access temporarily restricted. Please try again later.",
    "status": 429,
    "retry_after_seconds": 120,
    "request_id": "req_...",
    "session_bucket_hash": "sha256:..."
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

Never return or log a raw session token.

### 4. Add Cheap Private Route Health

Add an authenticated, no-model-token endpoint:

```text
GET /v1/private-route/health
```

Expected success:

```json
{
  "authenticated": true,
  "route": "near_private",
  "inference_available": true,
  "limited": false,
  "request_id": "req_..."
}
```

Expected limited response:

```json
{
  "authenticated": true,
  "route": "near_private",
  "inference_available": false,
  "limited": true,
  "reason": "private_route_rate_limited",
  "retry_after_seconds": 120,
  "request_id": "req_..."
}
```

The iOS app can then probe private-route readiness without burning a real model prompt.

## Validation Commands

AASA:

```sh
curl -i https://private.near.ai/.well-known/apple-app-site-association
```

Profile auth:

```sh
curl -i -H "Authorization: Bearer <redacted>" https://private.near.ai/v1/users/me
```

Future route health:

```sh
curl -i -H "Authorization: Bearer <redacted>" https://private.near.ai/v1/private-route/health
```

TestFlight manual pass:

1. Fresh install.
2. Sign in with web auth.
3. Force quit and relaunch.
4. Run Connection diagnostics.
5. Send a GLM 5.1 private prompt.
6. If private fails, confirm diagnostics show raw status/message and recovery copy matches the class:
   - `401` / session error -> sign in again.
   - `429` / `private_route_rate_limited` -> cooldown, no immediate private retry.
   - `503` / `private_route_capacity` -> one bounded private retry, then honest busy state.

## Bottom Line

The app can stop retry amplification and preserve better error truth. The durable fix still needs OVH/backend to serve AASA correctly, preserve auth headers, expose structured error codes, return retry metadata, and provide a cheap route-health endpoint.
