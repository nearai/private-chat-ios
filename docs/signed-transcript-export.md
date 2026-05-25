# NEAR Private Chat Signed Transcript Export

This document defines the first public verifier artifact for NEAR Private Chat:
`near-private-chat-transcript-v1.json`.

The goal is simple: a third party should be able to verify a transcript export
locally, without the iOS app and without uploading the transcript anywhere.

## Artifact

A v1 signed transcript contains:

- `schema`: always `near-private-chat-transcript-v1`.
- `schema_version`: always `1`.
- `exported_at`: ISO 8601 export timestamp.
- `conversation`: stable conversation metadata such as id, title, creation time,
  and optional hashed owner/account identifiers.
- `route`: provider and route metadata, including source mode, web-search state,
  project hash, privacy route, and other non-secret route labels.
- `attestation`: nonce, attestation report hash, optional model attestation hash,
  gateway signing address, fetch timestamp, and freshness label.
- `messages`: ordered transcript messages. Each message carries id, role,
  timestamp, content blocks, optional model id, optional response id, route
  metadata, sources, attachments, and a message hash.
- `hashes`: canonicalization identifier, hash algorithms, and transcript hash.
- `signature`: signing algorithm, public key, key id, signed payload label, and
  detached signature.

The machine-readable JSON schema lives at:

`verifier/schema/near-private-chat-transcript-v1.schema.json`

## Canonicalization

The verifier uses `near-private-chat-jcs-v1`, a small deterministic JSON profile:

- UTF-8 JSON only.
- Object keys are sorted lexicographically.
- Array order is preserved.
- Undefined values are omitted.
- Strings, booleans, null, and finite numbers use normal JSON encoding.

Message hashes are computed over each message object with only its `hash` field
removed.

The transcript hash is computed over the full transcript with:

- the top-level `signature` object removed;
- `hashes.transcript_hash` removed.

The signature signs this domain-separated payload:

```text
near-private-chat-transcript-v1
sha256:<transcript-hash>
```

## Signature

v1 uses Ed25519:

- `signature.algorithm`: `ed25519`
- `signature.key_scope`: `device-keychain` for iOS exports, `fixture` for
  verifier test fixtures
- `signature.public_key_pem`: PEM encoded public key
- `signature.signed_payload`: `schema-and-transcript-hash`
- `signature.signature`: base64 signature

The iOS app stores the export signing key in the device Keychain so repeated
exports from the same installed app have a stable verifier key id. Future
versions can add key discovery, certificate chains, or TEE-derived key metadata,
but v1 intentionally stays offline and content-local.

## Threat Model

Verification can prove:

- The transcript JSON has not changed since the transcript hash was signed.
- Each message still matches its recorded per-message hash.
- The signature matches the included public key.
- The export includes route and attestation metadata that can be independently
  reviewed by a verifier or auditor.

Verification cannot prove:

- The model output is factually true.
- The model behaved safely or well.
- The iOS UI displayed the same artifact before export.
- The included public key is trusted by a specific organization unless that
  organization publishes or pins the key.
- A URL, file, source, or attachment still exists at verification time.
- A stale or absent attestation means a route was malicious; it only means this
  artifact lacks fresh proof for that route.

In user-facing copy, describe this as proof of artifact integrity and route
evidence, not a promise that the answer is correct.

## Local Verification

From the repository root:

```bash
cd verifier
npm test
node bin/near-private-chat-verify.js fixtures/valid/near-private-chat-transcript-v1.valid.json
```

The verifier performs no network calls.
