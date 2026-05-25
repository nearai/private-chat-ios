"use strict";

const crypto = require("node:crypto");
const { clone, stableStringify, withoutKey } = require("./canonicalize");

const SUPPORTED_SCHEMA = "near-private-chat-transcript-v1";
const SUPPORTED_CANONICALIZATION = "near-private-chat-jcs-v1";
const SUPPORTED_HASH = "sha256";
const SUPPORTED_SIGNATURE = "ed25519";

function sha256Digest(value) {
  return `sha256:${crypto.createHash("sha256").update(value, "utf8").digest("hex")}`;
}

function messagePayload(message) {
  return withoutKey(message, "hash");
}

function computeMessageHash(message) {
  return sha256Digest(stableStringify(messagePayload(message)));
}

function transcriptPayload(transcript) {
  const payload = clone(transcript);
  delete payload.signature;
  if (payload.hashes) {
    delete payload.hashes.transcript_hash;
  }
  return payload;
}

function computeTranscriptHash(transcript) {
  return sha256Digest(stableStringify(transcriptPayload(transcript)));
}

function signaturePayload(transcriptHash) {
  return Buffer.from(`${SUPPORTED_SCHEMA}\n${transcriptHash}`, "utf8");
}

function verifySignature(transcript, transcriptHash) {
    const signature = transcript.signature || {};
    if (signature.algorithm !== SUPPORTED_SIGNATURE) {
        return { ok: false, detail: `unsupported algorithm ${signature.algorithm || "(missing)"}` };
    }
  if (signature.signed_payload !== "schema-and-transcript-hash") {
    return { ok: false, detail: "signature.signed_payload must be schema-and-transcript-hash" };
  }
  if (!signature.public_key_pem || !signature.signature) {
    return { ok: false, detail: "missing public_key_pem or signature" };
  }
  try {
    const publicKey = crypto.createPublicKey(signature.public_key_pem);
    const signatureBytes = Buffer.from(signature.signature, "base64");
    const ok = crypto.verify(null, signaturePayload(transcriptHash), publicKey, signatureBytes);
    return { ok, detail: ok ? undefined : "signature did not verify" };
  } catch (error) {
    return { ok: false, detail: error.message };
  }
}

function addCheck(checks, name, ok, detail) {
  checks.push({ name, ok: Boolean(ok), ...(detail ? { detail } : {}) });
}

function verifyTranscript(transcript) {
  const checks = [];
  const errors = [];
  const warnings = [];

  addCheck(checks, "schema", transcript.schema === SUPPORTED_SCHEMA, transcript.schema || "(missing)");
  addCheck(checks, "schema_version", transcript.schema_version === 1, String(transcript.schema_version));

  const hashes = transcript.hashes || {};
  addCheck(
    checks,
    "canonicalization",
    hashes.canonicalization === SUPPORTED_CANONICALIZATION,
    hashes.canonicalization || "(missing)"
  );
  addCheck(
    checks,
    "message_hash_algorithm",
    hashes.message_hash_algorithm === SUPPORTED_HASH,
    hashes.message_hash_algorithm || "(missing)"
  );
  addCheck(
    checks,
    "transcript_hash_algorithm",
    hashes.transcript_hash_algorithm === SUPPORTED_HASH,
    hashes.transcript_hash_algorithm || "(missing)"
  );

  const messages = Array.isArray(transcript.messages) ? transcript.messages : [];
  addCheck(checks, "messages_present", messages.length > 0, `${messages.length} message(s)`);

  const messageHashMismatches = [];
  for (const message of messages) {
    const expected = computeMessageHash(message);
    if (message.hash !== expected) {
      messageHashMismatches.push(`${message.id || "(missing id)"} expected ${expected} got ${message.hash || "(missing)"}`);
    }
  }
  addCheck(
    checks,
    "message_hashes",
    messageHashMismatches.length === 0,
    messageHashMismatches.length ? messageHashMismatches.join("; ") : `${messages.length} verified`
  );

  let computedTranscriptHash;
  try {
    computedTranscriptHash = computeTranscriptHash(transcript);
    addCheck(
      checks,
      "transcript_hash",
      hashes.transcript_hash === computedTranscriptHash,
      `computed ${computedTranscriptHash}`
    );
  } catch (error) {
    errors.push(`Could not compute transcript hash: ${error.message}`);
    addCheck(checks, "transcript_hash", false, error.message);
  }

  if (!transcript.attestation) {
    warnings.push("No attestation block is present; hash/signature verification can still pass, but route evidence is absent.");
  } else if (transcript.attestation.status === "unavailable") {
    warnings.push(transcript.attestation.warning || "Attestation was unavailable at export time; route evidence is absent.");
  } else {
    addCheck(checks, "attestation_nonce", Boolean(transcript.attestation.nonce), transcript.attestation.nonce || "(missing)");
    addCheck(
      checks,
      "attestation_hash",
      typeof transcript.attestation.report_hash === "string" && transcript.attestation.report_hash.startsWith("sha256:"),
      transcript.attestation.report_hash || "(missing)"
    );
  }

  const signatureResult = computedTranscriptHash ? verifySignature(transcript, computedTranscriptHash) : { ok: false, detail: "transcript hash failed" };
  addCheck(checks, "signature", signatureResult.ok, signatureResult.detail);

  for (const check of checks) {
    if (!check.ok) {
      errors.push(`${check.name} failed${check.detail ? ` (${check.detail})` : ""}`);
    }
  }

  return {
    ok: errors.length === 0,
    schema: transcript.schema,
    transcriptHash: computedTranscriptHash,
    checks,
    warnings,
    errors
  };
}

module.exports = {
  SUPPORTED_SCHEMA,
  computeMessageHash,
  computeTranscriptHash,
  sha256Digest,
  signaturePayload,
  stableStringify,
  verifyTranscript
};
