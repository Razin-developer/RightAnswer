import test from "node:test";
import assert from "node:assert/strict";

import { EmbeddingService } from "./embedding.service";

test("EmbeddingService normalizes text consistently", () => {
  process.env.RIGHT_ANSWER_EMBEDDING_BACKEND = "local-hash";
  process.env.RIGHT_ANSWER_EMBEDDING_DIMENSIONS = "32";
  const service = new EmbeddingService();
  assert.equal(service.normalizeText(" What is Photosynthesis? "), "what is photosynthesis");
});

test("EmbeddingService returns deterministic vectors", async () => {
  process.env.RIGHT_ANSWER_EMBEDDING_BACKEND = "local-hash";
  process.env.RIGHT_ANSWER_EMBEDDING_DIMENSIONS = "32";
  const service = new EmbeddingService();
  const a = await service.embedText("photosynthesis");
  const b = await service.embedText("photosynthesis");
  assert.deepEqual(a, b);
  assert.equal(a.length, 32);
});
