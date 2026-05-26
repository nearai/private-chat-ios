# NEAR Private Chat iOS Release Hardening Checklist

Before a production archive:

- Set `DEVELOPMENT_TEAM` and production bundle signing in the Xcode project or CI export options.
- Verify Release uses Swift optimization, strips debug symbols from copied products, and does not include debug-only token login.
- Confirm `PrivacyInfo.xcprivacy` lists required-reason APIs used by the app.
- Replace custom-scheme bearer-token callbacks with universal links plus one-time authorization-code exchange before shipping outside internal builds. The hosted auth service currently redirects Google/GitHub to the app by appending `/auth/callback?token=...&session_id=...` to the registered callback base; backend/web support must complete the code exchange path before public release.
- Add associated domains and entitlements when universal links are enabled.
- Archive with `CODE_SIGN_STYLE=Manual` or a locked CI profile, then inspect the exported `.ipa` for embedded logs, `.env`, `.token`, local configs, or simulator-only files.
- Run `xcodebuild test`, source smoke checks, and a signed export verifier fixture pass from a clean checkout.
