import { randomBytes, randomUUID } from "node:crypto";

import { Hono } from "hono";
import { Types } from "mongoose";

import type { AppEnv } from "../lib/auth";
import { optionalAuth, requireAuth } from "../lib/auth";
import { AppError, ok, requireString } from "../lib/http";
import { env } from "../config/env";
import { ChatModel, type ChatDocument } from "../models/chat.model";
import { ChatMessageModel } from "../models/chat-message.model";
import { ShareLinkModel } from "../models/share-link.model";
import { ContentShareModel } from "../models/content-share.model";

const chatRoutes = new Hono<AppEnv>();
const shareRoutes = new Hono<AppEnv>();
const contentRoutes = new Hono<AppEnv>();

const toChatJson = (chat: ChatDocument) => ({
  id: String(chat._id),
  _id: String(chat._id),
  localId: chat.localId,
  name: chat.name,
  subjectId: chat.subjectId,
  subjectName: chat.subjectName,
  chapterIds: chat.chapterIds ?? [],
  chapterNames: chat.chapterNames ?? [],
  isTemporary: chat.isTemporary ?? false,
  isPinned: chat.isPinned ?? false,
  createdAt: chat.createdAt.toISOString(),
  updatedAt: chat.updatedAt.toISOString(),
});

const toMessageJson = (message: {
  _id: unknown;
  localId?: string;
  chatId: unknown;
  role: string;
  content: string;
  imagePath?: string;
  responseLanguage?: string;
  responseLength?: string;
  reasoningLevel?: string;
  tokenCount?: number;
  cost?: number;
  sourceChunks?: string[];
  createdAt?: Date;
}) => ({
  id: String(message._id),
  _id: String(message._id),
  localId: message.localId,
  chatId: String(message.chatId),
  role: message.role,
  content: message.content,
  imagePath: message.imagePath,
  responseLanguage: message.responseLanguage,
  responseLength: message.responseLength ?? "normal",
  reasoningLevel: message.reasoningLevel ?? "mid",
  tokenCount: message.tokenCount ?? 0,
  cost: message.cost ?? 0,
  sourceChunks: message.sourceChunks ?? [],
  createdAt: (message.createdAt ?? new Date()).toISOString(),
});

const makeShareUrl = (token: string) => {
  const base = env.appUrl || `http://localhost:${env.port}`;
  return `${base.replace(/\/$/, "")}/api/share/${token}`;
};

const findOwnedChatByLocalId = async (ownerId: string, localId: string) => {
  const chat = await ChatModel.findOne({ ownerId, localId });
  if (!chat) {
    throw new AppError(404, "Chat not found", "CHAT_NOT_FOUND");
  }
  return chat as ChatDocument;
};

chatRoutes.get("/:chatId/messages", requireAuth, async (c) => {
  const user = c.get("user");
  const chatId = c.req.param("chatId");
  if (!Types.ObjectId.isValid(chatId)) {
    throw new AppError(400, "Invalid chat id", "VALIDATION_ERROR");
  }

  // Ownership check: without this, any authenticated caller could read any
  // other user's chat transcript just by guessing/enumerating a 24-hex-char
  // Mongo ObjectId (IDOR). Sharing has its own dedicated token-based flow
  // (see shareRoutes below) and must not be bypassed via this endpoint.
  const chat = await ChatModel.findOne({ _id: chatId, ownerId: user.id });
  if (!chat) {
    throw new AppError(404, "Chat not found", "CHAT_NOT_FOUND");
  }

  const messages = await ChatMessageModel.find({ chatId }).sort({
    createdAt: 1,
  });
  return ok(c, { messages: messages.map(toMessageJson) });
});

chatRoutes.use("*", requireAuth);

chatRoutes.get("/", async (c) => {
  const user = c.get("user");
  const chats = await ChatModel.find({ ownerId: user.id }).sort({
    isPinned: -1,
    updatedAt: -1,
  });
  return ok(c, {
    chats: chats.map((chat) => toChatJson(chat as ChatDocument)),
  });
});

chatRoutes.post("/", async (c) => {
  const user = c.get("user");
  const body = await c.req.json();
  const localId = requireString(
    body.localId ?? body.id ?? randomUUID(),
    "localId",
  );
  const name = requireString(body.name ?? "New Chat", "name");

  const chat = await ChatModel.findOneAndUpdate(
    { ownerId: user.id, localId },
    {
      $set: {
        name,
        subjectId: body.subjectId,
        subjectName: body.subjectName,
        chapterIds: Array.isArray(body.chapterIds) ? body.chapterIds : [],
        chapterNames: Array.isArray(body.chapterNames) ? body.chapterNames : [],
        isTemporary: Boolean(body.isTemporary),
        isPinned: Boolean(body.isPinned),
      },
    },
    { upsert: true, new: true, setDefaultsOnInsert: true },
  );

  return ok(c, { chat: toChatJson(chat as ChatDocument) });
});

chatRoutes.put("/by-local/:localId", async (c) => {
  const user = c.get("user");
  const chat = await findOwnedChatByLocalId(user.id, c.req.param("localId"));
  const body = await c.req.json();
  const allowed = [
    "name",
    "subjectId",
    "subjectName",
    "chapterIds",
    "chapterNames",
    "isTemporary",
    "isPinned",
  ];

  for (const key of allowed) {
    if (key in body) {
      chat.set(key, body[key]);
    }
  }
  await chat.save();

  return ok(c, { chat: toChatJson(chat) });
});

chatRoutes.delete("/by-local/:localId", async (c) => {
  const user = c.get("user");
  const chat = await findOwnedChatByLocalId(user.id, c.req.param("localId"));
  await ChatMessageModel.deleteMany({ chatId: chat._id });
  await ChatModel.deleteOne({ _id: chat._id });
  return ok(c, { deleted: true });
});

chatRoutes.post("/by-local/:localId/messages", async (c) => {
  const user = c.get("user");
  const chat = await findOwnedChatByLocalId(user.id, c.req.param("localId"));
  const body = await c.req.json();
  const localId = requireString(
    body.localId ?? body.id ?? randomUUID(),
    "localId",
  );

  const message = await ChatMessageModel.findOneAndUpdate(
    { chatId: chat._id, localId },
    {
      $set: {
        ownerId: user.id,
        chatId: chat._id,
        localId,
        role: body.role ?? "assistant",
        content: body.content ?? "",
        imagePath: body.imagePath,
        responseLanguage: body.responseLanguage,
        responseLength: body.responseLength ?? "normal",
        reasoningLevel: body.reasoningLevel ?? "mid",
        tokenCount: Number(body.tokenCount ?? 0),
        cost: Number(body.cost ?? 0),
        sourceChunks: Array.isArray(body.sourceChunks) ? body.sourceChunks : [],
      },
    },
    { upsert: true, new: true, setDefaultsOnInsert: true },
  );

  chat.updatedAt = new Date();
  await chat.save();
  return ok(c, { message: toMessageJson(message) });
});

chatRoutes.post("/by-local/:localId/share", async (c) => {
  const user = c.get("user");
  const chat = await findOwnedChatByLocalId(user.id, c.req.param("localId"));
  const body = await c.req.json().catch(() => ({}));
  const token = randomBytes(24).toString("base64url");
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

  await ShareLinkModel.create({
    ownerId: user.id,
    token,
    type: "chat",
    refId: chat._id,
    accessLevel: body.accessLevel ?? "full",
    expiresAt,
  });

  return ok(c, {
    token,
    url: makeShareUrl(token),
    expiresAt: expiresAt.toISOString(),
  });
});

shareRoutes.get("/:token", optionalAuth, async (c) => {
  const token = c.req.param("token");
  const share = await ShareLinkModel.findOne({
    token,
    expiresAt: { $gt: new Date() },
  });

  if (!share) {
    throw new AppError(
      404,
      "Share link is invalid or expired",
      "SHARE_NOT_FOUND",
    );
  }

  await ShareLinkModel.updateOne({ _id: share._id }, { $inc: { useCount: 1 } });

  if (share.type === "content") {
    const content = await ContentShareModel.findById(share.refId);
    if (!content) {
      throw new AppError(404, "Shared content not found", "SHARE_NOT_FOUND");
    }

    return new Response(content.bytes, {
      headers: {
        "Content-Type": content.mimeType,
        "Content-Disposition": `attachment; filename="${content.filename.replace(/"/g, "")}"`,
      },
    });
  }

  const chat = await ChatModel.findById(share.refId);
  if (!chat) {
    throw new AppError(404, "Shared chat not found", "SHARE_NOT_FOUND");
  }

  const messages = await ChatMessageModel.find({ chatId: chat._id }).sort({
    createdAt: 1,
  });
  return ok(c, {
    chat: toChatJson(chat as ChatDocument),
    messages: messages.map(toMessageJson),
    expiresAt: share.expiresAt.toISOString(),
  });
});

// MongoDB's hard document-size ceiling is 16MB; the whole file is embedded
// as a `bytes` field on the document, so anything close to that limit would
// fail with an opaque Mongo error. Cap well under that and fail fast with a
// clear error instead of buffering unbounded request bodies into memory.
const MAX_CONTENT_SHARE_BYTES = 10 * 1024 * 1024;

contentRoutes.post("/", requireAuth, async (c) => {
  const user = c.get("user");
  const form = await c.req.raw.formData();
  const file = form.get("file");
  if (!(file instanceof File)) {
    throw new AppError(400, "file is required", "VALIDATION_ERROR");
  }
  if (file.size > MAX_CONTENT_SHARE_BYTES) {
    throw new AppError(
      413,
      `file exceeds the ${MAX_CONTENT_SHARE_BYTES / (1024 * 1024)}MB limit`,
      "FILE_TOO_LARGE",
    );
  }

  const metadataRaw = form.get("metadata");
  const metadata =
    typeof metadataRaw === "string" && metadataRaw.trim()
      ? JSON.parse(metadataRaw)
      : {};
  const content = await ContentShareModel.create({
    ownerId: user.id,
    filename: file.name || "content.zip",
    mimeType: file.type || "application/zip",
    metadata,
    bytes: Buffer.from(await file.arrayBuffer()),
  });

  const token = randomBytes(24).toString("base64url");
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000);
  await ShareLinkModel.create({
    ownerId: user.id,
    token,
    type: "content",
    refId: content._id,
    expiresAt,
  });

  return ok(c, {
    token,
    url: makeShareUrl(token),
    expiresAt: expiresAt.toISOString(),
  });
});

export { chatRoutes, shareRoutes, contentRoutes, toMessageJson };
