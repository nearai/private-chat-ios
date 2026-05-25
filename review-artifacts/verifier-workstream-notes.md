# Verifier Workstream Notes

Date: 2026-05-24

Implemented the first local slice of Packet 0c from
`NEARPrivateChatIOS-competitive-onboarding-roadmap.md`.

Scope intentionally stayed outside the Swift app surface:

- Added a versioned signed transcript schema.
- Added a no-dependency Node verifier CLI.
- Added valid and tampered fixtures.
- Added verifier tests that prove valid exports pass and tampered exports fail.
- Added threat-model documentation for reviewers.

Follow-up before app integration:

- Add a small Swift export hook that emits `near-private-chat-transcript-v1.json`
  once product decides where signing keys live.
- Publish or pin trusted verifier public keys; fixtures only prove mechanics.
- Add a local browser drag-and-drop verifier page if Packet 0c expands beyond
  command-line validation.
