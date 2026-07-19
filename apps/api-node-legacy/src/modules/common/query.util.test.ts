import test from "node:test";
import assert from "node:assert/strict";

import { detectContentPreference, detectDifficulty, sanitizeQuestion } from "./query.util";

test("sanitizeQuestion strips prompt injection punctuation", () => {
  assert.equal(sanitizeQuestion("{Explain}<photosynthesis>`"), "Explain photosynthesis");
});

test("detectDifficulty recognizes simple definitions", () => {
  assert.equal(detectDifficulty("What is photosynthesis?"), "simple");
});

test("detectContentPreference recognizes diagram questions", () => {
  assert.equal(detectContentPreference("Explain the diagram of the leaf"), "diagram_ref");
});
