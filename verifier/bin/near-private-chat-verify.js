#!/usr/bin/env node

const { readFileSync } = require("node:fs");
const { basename } = require("node:path");
const { verifyTranscript } = require("../lib/verify");

function usage() {
  console.error("Usage: near-private-chat-verify <transcript.json> [--json]");
}

const args = process.argv.slice(2);
const jsonOutput = args.includes("--json");
const transcriptPath = args.find((arg) => !arg.startsWith("--"));

if (!transcriptPath || args.includes("--help") || args.includes("-h")) {
  usage();
  process.exit(transcriptPath ? 0 : 2);
}

let transcript;
try {
  transcript = JSON.parse(readFileSync(transcriptPath, "utf8"));
} catch (error) {
  const result = {
    ok: false,
    file: transcriptPath,
    errors: [`Could not read JSON: ${error.message}`],
    checks: []
  };
  if (jsonOutput) {
    console.log(JSON.stringify(result, null, 2));
  } else {
    console.error(`FAIL ${basename(transcriptPath)}`);
    console.error(`- ${result.errors[0]}`);
  }
  process.exit(1);
}

const result = verifyTranscript(transcript);
result.file = transcriptPath;

if (jsonOutput) {
  console.log(JSON.stringify(result, null, 2));
} else {
  console.log(`${result.ok ? "PASS" : "FAIL"} ${basename(transcriptPath)}`);
  for (const check of result.checks) {
    console.log(`${check.ok ? "  ok" : "  no"}  ${check.name}${check.detail ? `: ${check.detail}` : ""}`);
  }
  for (const warning of result.warnings) {
    console.log(`  warn ${warning}`);
  }
  for (const error of result.errors) {
    console.log(`  err ${error}`);
  }
  if (result.transcriptHash) {
    console.log(`  hash ${result.transcriptHash}`);
  }
}

process.exit(result.ok ? 0 : 1);
