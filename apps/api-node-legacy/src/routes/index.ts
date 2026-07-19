import { Hono } from "hono";

import type { AppEnv } from "../lib/auth";
import { requireAuth } from "../lib/auth";
import { authRoutes } from "./auth.routes";
import { aiRoutes, handleAiChat } from "./ai.routes";
import { chatRoutes, contentRoutes, shareRoutes } from "./chat.routes";
import { env } from "../config/env";

export const createApiRoutes = () => {
  const api = new Hono<AppEnv>();

  api.get("/health", (c) =>
    c.json({
      ok: true,
      service: "right-answer-api",
      aiMethod: env.aiMethod,
      models: {
        simple: env.simpleModel,
        reasoning: env.reasoningModel,
        embedding: env.embeddingModel,
        rerank: env.rerankModel,
      },
    }),
  );

  api.route("/auth", authRoutes);
  api.route("/ai", aiRoutes);
  api.route("/chats", chatRoutes);
  api.route("/share", shareRoutes);
  api.route("/content", contentRoutes);

  api.post("/ask", requireAuth, handleAiChat);

  return api;
};
