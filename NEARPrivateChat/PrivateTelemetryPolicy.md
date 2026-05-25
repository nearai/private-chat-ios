# NEAR Private Chat Telemetry Policy

NEAR Private Chat may count product-shape events locally so the team can understand whether onboarding, composer, model-picker, sharing, streaming, and attestation surfaces are usable. The foundation is local-only in this build: it does not upload analytics and it does not make analytics network calls.

## Default

- Usage sharing is off by default.
- Local diagnostics can be exported by a tester to inspect aggregate counters.
- The app privacy manifest should remain unchanged unless analytics upload is explicitly added later.

## Allowed Event Schema

Only these event names are allowed:

- `setup_goal_selected`
- `setup_completed_or_skipped`
- `focus_mode_changed`
- `prompt_chip_used`
- `attestation_chip_tapped`
- `attestation_refresh_succeeded_or_failed`
- `model_picker_tab_opened`
- `share_preview_opened`
- `stream_reconnected`
- `generic_error`

Events may include only bounded enum values such as setup goal, focus mode, model-picker tab, success/failure, or a generic error category.

## Forbidden Content

Telemetry must never include:

- Prompts
- Responses
- File names
- Source URLs
- Account identifiers
- Conversation identifiers
- Transcript identifiers
- Raw model outputs
- Raw event streams
- Raw error bodies

The Swift telemetry schema is built from enums rather than free-form strings so these fields cannot be encoded accidentally.

## Aggregation

Counters are aggregated on device by:

- Day
- App version
- Profile bucket

Future upload work must add documented differential-privacy noise, a user-visible setting, privacy-copy review, manifest review, and k-anonymous dashboard thresholds before any metric is exposed.
