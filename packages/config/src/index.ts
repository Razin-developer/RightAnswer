export const APP_NAME = "Right Answer";
export const APP_SLUG = "right-answer";
export const STORAGE_ROOT = "storage";

export const APPROVED_TEXTBOOK_SOURCE_DOMAINS = [
  "scert.kerala.gov.in",
  "samagra.kite.kerala.gov.in",
  "education.kerala.gov.in",
] as const;

export const CORE_SUBJECT_CODES = [
  "biology",
  "physics",
  "chemistry",
  "mathematics",
  "social-science",
  "english",
  "malayalam",
] as const;

export const EMBEDDING_MODEL_DEFAULT = "Qwen/Qwen3-Embedding-4B";
export const DEFAULT_EMBEDDING_BACKEND = process.env.RIGHT_ANSWER_EMBEDDING_BACKEND ?? "hf-transformers";

export function resolveEmbeddingDimensions(modelId: string, explicitDimensions?: string | number | null) {
  if (explicitDimensions !== undefined && explicitDimensions !== null && String(explicitDimensions).trim()) {
    return Number(explicitDimensions);
  }

  if (modelId.includes("Qwen3-Embedding-8B")) {
    return 4096;
  }

  if (modelId.includes("Qwen3-Embedding-4B")) {
    return 2560;
  }

  return 1024;
}

export const DEFAULT_EMBEDDING_MODEL = process.env.RIGHT_ANSWER_EMBEDDING_MODEL ?? EMBEDDING_MODEL_DEFAULT;
export const DEFAULT_EMBEDDING_DIMENSIONS = resolveEmbeddingDimensions(
  DEFAULT_EMBEDDING_MODEL,
  process.env.RIGHT_ANSWER_EMBEDDING_DIMENSIONS,
);
