import { randomUUID } from "node:crypto";

import { Hono } from "hono";
import type { Handler } from "hono";

import type { AppEnv } from "../lib/auth";
import { optionalAuth } from "../lib/auth";
import { AppError, ok, requireString } from "../lib/http";
import { env } from "../config/env";
import { aiService, type ChatPromptMessage } from "../services/ai.service";
import { ChatModel, type ChatDocument } from "../models/chat.model";
import { ChatMessageModel } from "../models/chat-message.model";
import { toMessageJson } from "./chat.routes";

const aiRoutes = new Hono<AppEnv>();

const normalizeHistory = (value: unknown): ChatPromptMessage[] => {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .map((item) => {
      if (!item || typeof item !== "object") {
        return null;
      }
      const record = item as Record<string, unknown>;
      const role = record.role;
      const content = record.content;
      if (
        (role !== "user" && role !== "assistant" && role !== "system") ||
        typeof content !== "string"
      ) {
        return null;
      }
      return { role, content };
    })
    .filter((item): item is ChatPromptMessage => item !== null);
};

const normalizeStringArray = (value: unknown) =>
  Array.isArray(value)
    ? value.filter(
        (item): item is string =>
          typeof item === "string" && item.trim().length > 0,
      )
    : [];

const findOrCreateChat = async (
  userId: string,
  body: Record<string, unknown>,
) => {
  const chatLocalId =
    typeof body.chatLocalId === "string" && body.chatLocalId.trim()
      ? body.chatLocalId.trim()
      : undefined;

  if (!chatLocalId) {
    return null;
  }

  const name =
    typeof body.chatName === "string" && body.chatName.trim()
      ? body.chatName.trim()
      : "New Chat";

  return (await ChatModel.findOneAndUpdate(
    { ownerId: userId, localId: chatLocalId },
    {
      $setOnInsert: {
        ownerId: userId,
        localId: chatLocalId,
        name,
        subjectId: body.subjectId,
        subjectName: body.subjectName,
        chapterIds: normalizeStringArray(body.chapterIds),
        chapterNames: normalizeStringArray(body.chapterNames),
        isTemporary: false,
        isPinned: false,
      },
    },
    { upsert: true, new: true, setDefaultsOnInsert: true },
  )) as ChatDocument;
};

aiRoutes.use("*", optionalAuth);

const handleAiChat: Handler<AppEnv> = async (c) => {
  const user = c.get("user") as { id: string } | undefined;
  const body = (await c.req.json()) as Record<string, unknown>;
  const question = requireString(
    body.question ?? body.message ?? body.content,
    "question",
  );
  const systemPrompt =
    typeof body.systemPrompt === "string" ? body.systemPrompt : undefined;
  const responseLength =
    typeof body.responseLength === "string" ? body.responseLength : "normal";
  const reasoningLevel =
    typeof body.reasoningLevel === "string" ? body.reasoningLevel : "mid";
  const responseLanguage =
    typeof body.responseLanguage === "string"
      ? body.responseLanguage
      : undefined;
  const subjectId =
    typeof body.subjectId === "string" ? body.subjectId : undefined;
  const subjectName =
    typeof body.subjectName === "string" ? body.subjectName : undefined;
  const chapterIds = normalizeStringArray(body.chapterIds);
  const chapterNames = normalizeStringArray(body.chapterNames);
  const contexts = normalizeStringArray(body.contexts ?? body.sourceChunks);
  const history = normalizeHistory(body.history);
  const temperature =
    typeof body.temperature === "number" ? body.temperature : undefined;
  const maxTokens =
    typeof body.maxTokens === "number"
      ? body.maxTokens
      : typeof body.max_tokens === "number"
        ? body.max_tokens
        : undefined;
  const jsonMode = body.jsonMode == true || body.responseFormat == "json";
  const richAnswer = body.richAnswer === true || body.answerFormat === "rich";

  const result = await aiService.ask({
    question,
    systemPrompt,
    history,
    responseLength,
    reasoningLevel,
    responseLanguage,
    subjectId,
    subjectName,
    chapterIds,
    chapterNames,
    contexts,
    temperature,
    maxTokens,
    jsonMode,
    richAnswer,
  });

  const chat = user ? await findOrCreateChat(user.id, body) : null;
  let assistantMessage: unknown;
  if (user && chat) {
    await ChatMessageModel.create({
      ownerId: user.id,
      chatId: chat._id,
      localId:
        typeof body.userMessageLocalId === "string"
          ? body.userMessageLocalId
          : randomUUID(),
      role: "user",
      content: question,
      responseLanguage,
      responseLength,
      reasoningLevel,
    }).catch((error: unknown) => {
      if ((error as { code?: number }).code !== 11000) {
        throw error;
      }
    });

    assistantMessage = await ChatMessageModel.create({
      ownerId: user.id,
      chatId: chat._id,
      localId:
        typeof body.assistantMessageLocalId === "string"
          ? body.assistantMessageLocalId
          : randomUUID(),
      role: "assistant",
      content: result.content,
      responseLanguage,
      responseLength,
      reasoningLevel,
      tokenCount: result.outputTokens,
      sourceChunks: result.sourceChunks,
    });

    chat.updatedAt = new Date();
    await chat.save();
  }

  return ok(c, {
    answer: {
      content: result.content,
      servedFrom: result.servedFrom,
      model: result.model,
      provider: result.provider,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
      sourceChunks: result.sourceChunks,
    },
    content: result.content,
    servedFrom: result.servedFrom,
    message: assistantMessage
      ? toMessageJson(assistantMessage as never)
      : undefined,
  });
};

aiRoutes.post("/chat", handleAiChat);

aiRoutes.post("/embeddings", async (c) => {
  const body = await c.req.json();
  const text = requireString(body?.text ?? body?.input, "text");
  return ok(c, {
    model: env.embeddingModel,
    embedding: await aiService.embedQuestion(text),
  });
});

aiRoutes.post("/rerank", async (c) => {
  const body = await c.req.json();
  const question = requireString(body?.question ?? body?.query, "question");
  const documents = normalizeStringArray(body?.documents);
  if (!documents.length) {
    throw new AppError(400, "documents is required", "VALIDATION_ERROR");
  }

  return ok(c, { documents: await aiService.rerank(question, documents) });
});

export { aiRoutes, handleAiChat };
