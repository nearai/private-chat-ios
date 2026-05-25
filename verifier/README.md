# NEAR Private Chat Verifier

Offline verifier for `near-private-chat-transcript-v1.json` signed transcript
exports.

## Usage

```bash
cd verifier
node bin/near-private-chat-verify.js fixtures/valid/near-private-chat-transcript-v1.valid.json
npm test
```

When packaged publicly, the intended CLI shape is:

```bash
npx near-private-chat-verify transcript.json
```

The verifier is content-local. It reads one JSON file, recomputes message and
transcript hashes, verifies the Ed25519 signature with the included public key,
prints pass/fail checks, and exits non-zero on failure. It does not call NEAR,
OpenAI, model providers, attestation endpoints, or any other network service.
iOS exports use a device-local Keychain signing identity, so repeated exports
from the same install should show the same `device-ed25519:*` key id.

## Browser Verifier

Open `public/index.html` in a browser and drop a signed transcript JSON file.
The page runs locally, performs no network calls, and verifies the same message
hash and transcript hash contract as the CLI. Ed25519 signature verification is
attempted through WebCrypto when the browser supports it; the CLI remains the
reference verifier for automation and older browsers.

## Format

The schema is in `schema/near-private-chat-transcript-v1.schema.json`. The
long-form format, canonicalization, signature, and threat model notes are in
`../docs/signed-transcript-export.md`.

## Fixtures

- `fixtures/valid/near-private-chat-transcript-v1.valid.json` is a tiny valid
  export signed with a throwaway fixture key.
- `fixtures/tampered/near-private-chat-transcript-v1.tampered-message.json`
  changes assistant text without updating the hashes or signature.
- `fixtures/tampered/near-private-chat-transcript-v1.tampered-signature.json`
  changes the detached signature.

Run all fixture checks:

```bash
npm test
```

## Trust Notes

This verifier proves artifact integrity against the public key embedded in the
export. Production trust still needs key publication or pinning, plus policy for
which keys/routes/attestations a relying party accepts.
