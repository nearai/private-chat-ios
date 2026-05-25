"use strict";

function stableStringify(value) {
  if (value === null) {
    return "null";
  }
  if (Array.isArray(value)) {
    return `[${value.map(stableStringify).join(",")}]`;
  }
  switch (typeof value) {
    case "boolean":
      return value ? "true" : "false";
    case "number":
      if (!Number.isFinite(value)) {
        throw new Error("Canonical JSON cannot encode non-finite numbers.");
      }
      return JSON.stringify(value);
    case "string":
      return JSON.stringify(value);
    case "object": {
      const entries = Object.entries(value)
        .filter(([, entryValue]) => entryValue !== undefined)
        .sort(([left], [right]) => left.localeCompare(right));
      return `{${entries.map(([key, entryValue]) => `${JSON.stringify(key)}:${stableStringify(entryValue)}`).join(",")}}`;
    }
    default:
      throw new Error(`Canonical JSON cannot encode ${typeof value}.`);
  }
}

function withoutKey(value, keyToRemove) {
  if (Array.isArray(value)) {
    return value.map((entry) => withoutKey(entry, keyToRemove));
  }
  if (!value || typeof value !== "object") {
    return value;
  }
  return Object.fromEntries(
    Object.entries(value)
      .filter(([key]) => key !== keyToRemove)
      .map(([key, entryValue]) => [key, withoutKey(entryValue, keyToRemove)])
  );
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

module.exports = {
  clone,
  stableStringify,
  withoutKey
};
