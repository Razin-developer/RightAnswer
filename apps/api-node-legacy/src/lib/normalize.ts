import { createHash } from "node:crypto";

export const normalizeQuestion = (value: string) =>
  value
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();

export const stableHash = (value: string) =>
  createHash("sha256").update(value).digest("hex");

export const estimateTokens = (value: string) =>
  Math.max(1, Math.ceil(value.length / 4));

export const cosineSimilarity = (a: number[], b: number[]) => {
  if (!a.length || a.length !== b.length) {
    return 0;
  }

  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let index = 0; index < a.length; index += 1) {
    dot += a[index] * b[index];
    normA += a[index] * a[index];
    normB += b[index] * b[index];
  }

  if (!normA || !normB) {
    return 0;
  }

  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
};
