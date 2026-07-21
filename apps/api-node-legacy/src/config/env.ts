export type AiMethod = "hackai" | "openrouter";

const readEnv = (...names: string[]) => {
  for (const name of names) {
    const value = process.env[name];
    if (value && value.trim()) {
      return value.trim();
    }
  }
  return "";
};

const rawAiMethod = readEnv(
  "AI_METHOD",
  "AI_METHOS",
  "ai_method",
  "ai_methos",
).toLowerCase();
const aiMethod: AiMethod = rawAiMethod === "hackai" ? "hackai" : "openrouter";

const nodeEnv = process.env.NODE_ENV ?? "development";

const resolveJwtSecret = () => {
  const configured = readEnv("JWT_SECRET");
  if (configured) {
    return configured;
  }
  if (nodeEnv === "production") {
    // Never fall back to a shared hardcoded secret in production: anyone
    // who reads this source (it's a public/legacy repo) could forge tokens
    // for any user, including admins.
    throw new Error(
      "JWT_SECRET environment variable is required in production",
    );
  }
  return "right-answer-dev-secret";
};

export const env = {
  nodeEnv,
  port: Number(process.env.PORT ?? 4000),
  mongoUri:
    readEnv("MONGODB_URI", "MONGO_URI") ||
    "mongodb://127.0.0.1:27017/right-answer",
  jwtSecret: resolveJwtSecret(),
  jwtExpiresIn: readEnv("JWT_EXPIRES_IN") || "30d",
  appUrl: readEnv("APP_URL", "PUBLIC_APP_URL") || "",
  corsOrigins: readEnv("CORS_ORIGINS")
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean),

  aiMethod,
  openRouterApiKey: readEnv("OPENROUTER_API_KEY", "openrouter_api_key"),
  hackAiApiKey: readEnv("HACKAI_API_KEY", "hackai_api_key", "HACKCLUB_API_KEY"),
  openRouterBaseUrl:
    readEnv("OPENROUTER_BASE_URL") || "https://openrouter.ai/api/v1",
  hackAiBaseUrl:
    readEnv("HACKAI_BASE_URL") || "https://ai.hackclub.com/proxy/v1",

  embeddingModel:
    readEnv("AI_EMBEDDING_MODEL") || "perplexity/pplx-embed-v1-0.6b",
  rerankModel:
    readEnv("AI_RERANK_MODEL") || "nvidia/llama-nemotron-rerank-vl-1b-v2:free",
  simpleModel: readEnv("AI_SIMPLE_MODEL") || "google/gemma-3-12b-it",
  reasoningModel: readEnv("AI_REASONING_MODEL") || "google/gemma-4-31b-it",
  semanticCacheThreshold: Number(readEnv("SEMANTIC_CACHE_THRESHOLD") || 0.9),
  answerCacheLimit: Number(readEnv("ANSWER_CACHE_SCAN_LIMIT") || 100),
};

export const activeAiProvider = () => {
  if (env.aiMethod === "hackai") {
    return {
      name: "hackai" as const,
      apiKey: env.hackAiApiKey,
      baseUrl: env.hackAiBaseUrl,
    };
  }

  return {
    name: "openrouter" as const,
    apiKey: env.openRouterApiKey,
    baseUrl: env.openRouterBaseUrl,
  };
};
