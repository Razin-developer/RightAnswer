import { OpenRouter } from "@openrouter/sdk";

import { activeAiProvider, env } from "../config/env";
import { AnswerCacheModel } from "../models/answer-cache.model";
import {
  cosineSimilarity,
  estimateTokens,
  normalizeQuestion,
  stableHash,
} from "../lib/normalize";
import { AppError } from "../lib/http";
import { buildRichAnswerSystemPrompt } from "../prompts/rich-answer.prompt";

type ChatRole = "system" | "user" | "assistant";

export type ChatPromptMessage = {
  role: ChatRole;
  content: string;
};

export type AskInput = {
  question: string;
  systemPrompt?: string;
  history?: ChatPromptMessage[];
  responseLength?: string;
  reasoningLevel?: string;
  responseLanguage?: string;
  subjectId?: string;
  subjectName?: string;
  chapterIds?: string[];
  chapterNames?: string[];
  contexts?: string[];
  temperature?: number;
  maxTokens?: number;
  jsonMode?: boolean;
  richAnswer?: boolean;
};

type ProviderCallResult = {
  content: string;
  model: string;
  provider: string;
  inputTokens: number;
  outputTokens: number;
};

const providerHeaders = () => {
  const provider = activeAiProvider();
  if (!provider.apiKey) {
    throw new AppError(
      500,
      `Missing ${provider.name === "hackai" ? "HACKAI_API_KEY" : "OPENROUTER_API_KEY"}`,
      "AI_PROVIDER_NOT_CONFIGURED",
    );
  }

  return {
    provider,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${provider.apiKey}`,
      "HTTP-Referer": env.appUrl || "http://localhost",
      "X-OpenRouter-Title": "Right Answer",
    },
  };
};

const chooseModel = (input: AskInput) => {
  const reasoningLevel = input.reasoningLevel ?? "mid";
  const responseLength = input.responseLength ?? "normal";
  const longQuestion = input.question.length > 320;

  if (reasoningLevel === "high" || responseLength === "large" || longQuestion) {
    return env.reasoningModel;
  }

  return env.simpleModel;
};

const buildExactKey = (input: AskInput, normalizedQuestion: string) =>
  stableHash(
    [
      normalizedQuestion,
      input.responseLanguage ?? "",
      input.responseLength ?? "normal",
      input.reasoningLevel ?? "mid",
      input.systemPrompt ?? "",
      input.jsonMode ? "json" : "",
      input.richAnswer ? "rich-answer-v1" : "",
      input.subjectId ?? "",
      input.subjectName ?? "",
      stableHash((input.contexts ?? []).join("\n\n")),
      ...(input.chapterIds ?? []),
    ].join("|"),
  );

const buildBaseSystemPrompt = (input: AskInput, contextBlock: string) => {
  if (input.systemPrompt?.trim()) {
    return contextBlock
      ? `${input.systemPrompt.trim()}\n\nStudy context:\n${contextBlock}`
      : input.systemPrompt.trim();
  }

  const length = input.responseLength ?? "normal";
  const reasoning = input.reasoningLevel ?? "mid";
  const language = input.responseLanguage?.trim();

  return [
    "You are Right Answer, a careful study assistant for school students.",
    "Answer directly, stay grounded in supplied study context when it exists, and avoid inventing textbook facts.",
    input.subjectName ? `Subject: ${input.subjectName}.` : "",
    input.chapterNames?.length
      ? `Chapters: ${input.chapterNames.join(", ")}.`
      : "",
    language ? `Respond in ${language}.` : "",
    `Response length: ${length}.`,
    `Reasoning depth: ${reasoning}.`,
    contextBlock ? `Study context:\n${contextBlock}` : "",
  ]
    .filter(Boolean)
    .join("\n");
};

const buildSystemPrompt = (
  input: AskInput,
  contextBlock: string,
  selectedContextCount: number,
) => {
  if (!input.richAnswer || input.jsonMode) {
    return buildBaseSystemPrompt(input, contextBlock);
  }

  return buildRichAnswerSystemPrompt({
    input,
    baseInstructions: buildBaseSystemPrompt(input, ""),
    contextBlock,
    selectedContextCount,
  });
};

const parseChatContent = (response: unknown) => {
  const value = response as {
    choices?: Array<{ message?: { content?: unknown } }>;
  };
  const content = value.choices?.[0]?.message?.content;
  if (typeof content === "string") {
    return content.trim();
  }
  return "";
};

export class AiService {
  async ask(input: AskInput) {
    const normalizedQuestion = normalizeQuestion(input.question);
    if (!normalizedQuestion) {
      throw new AppError(400, "question is required", "VALIDATION_ERROR");
    }

    const exactKey = buildExactKey(input, normalizedQuestion);
    const exactHit = await AnswerCacheModel.findOne({ exactKey });
    if (exactHit) {
      await AnswerCacheModel.updateOne(
        { _id: exactHit._id },
        { $inc: { hitCount: 1 } },
      );
      return {
        content: exactHit.answer,
        servedFrom: "exact_cache",
        model: exactHit.model,
        provider: exactHit.provider,
        inputTokens: exactHit.inputTokens,
        outputTokens: exactHit.outputTokens,
        sourceChunks: exactHit.sourceChunks,
      };
    }

    const questionEmbedding = await this.embedQuestion(
      normalizedQuestion,
    ).catch(() => []);
    if (questionEmbedding.length) {
      const semanticHit = await this.lookupSemanticCache(
        input,
        questionEmbedding,
      );
      if (semanticHit) {
        await AnswerCacheModel.updateOne(
          { _id: semanticHit._id },
          { $inc: { hitCount: 1 } },
        );
        return {
          content: semanticHit.answer,
          servedFrom: "semantic_cache",
          model: semanticHit.model,
          provider: semanticHit.provider,
          inputTokens: semanticHit.inputTokens,
          outputTokens: semanticHit.outputTokens,
          sourceChunks: semanticHit.sourceChunks,
        };
      }
    }

    const sourceChunks = await this.prepareContext(input);
    const generation = await this.generateAnswer(input, sourceChunks);

    await AnswerCacheModel.create({
      exactKey,
      normalizedQuestion,
      question: input.question,
      answer: generation.content,
      embedding: questionEmbedding,
      model: generation.model,
      provider: generation.provider,
      language: input.responseLanguage,
      responseLength: input.responseLength ?? "normal",
      reasoningLevel: input.reasoningLevel ?? "mid",
      subjectId: input.subjectId,
      subjectName: input.subjectName,
      chapterIds: input.chapterIds ?? [],
      sourceChunks,
      inputTokens: generation.inputTokens,
      outputTokens: generation.outputTokens,
    });

    return {
      ...generation,
      servedFrom: "model",
      sourceChunks,
    };
  }

  async embedQuestion(text: string) {
    const { provider, headers } = providerHeaders();
    const response = await fetch(`${provider.baseUrl}/embeddings`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        model: env.embeddingModel,
        input: text,
      }),
    });

    if (!response.ok) {
      return [];
    }

    const data = (await response.json()) as {
      data?: Array<{ embedding?: number[] }>;
    };
    return data.data?.[0]?.embedding ?? [];
  }

  async rerank(question: string, documents: string[]) {
    if (documents.length <= 1) {
      return documents;
    }

    const { provider, headers } = providerHeaders();
    const response = await fetch(`${provider.baseUrl}/rerank`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        model: env.rerankModel,
        query: question,
        documents,
      }),
    });

    if (!response.ok) {
      return this.keywordRerank(question, documents);
    }

    const data = (await response.json()) as {
      results?: Array<{ index: number; relevance_score?: number }>;
    };

    const ranked = (data.results ?? [])
      .filter((item) => Number.isInteger(item.index) && documents[item.index])
      .sort((a, b) => (b.relevance_score ?? 0) - (a.relevance_score ?? 0))
      .map((item) => documents[item.index]);

    return ranked.length ? ranked : this.keywordRerank(question, documents);
  }

  private async lookupSemanticCache(input: AskInput, embedding: number[]) {
    const candidates = await AnswerCacheModel.find({
      embedding: { $exists: true, $ne: [] },
      language: input.responseLanguage,
      responseLength: input.responseLength ?? "normal",
      reasoningLevel: input.reasoningLevel ?? "mid",
      ...(input.subjectId ? { subjectId: input.subjectId } : {}),
    })
      .sort({ updatedAt: -1 })
      .limit(env.answerCacheLimit);

    let best: { item: (typeof candidates)[number]; score: number } | null =
      null;
    for (const item of candidates) {
      const score = cosineSimilarity(item.embedding ?? [], embedding);
      if (!best || score > best.score) {
        best = { item, score };
      }
    }

    return best && best.score >= env.semanticCacheThreshold ? best.item : null;
  }

  private async prepareContext(input: AskInput) {
    const contexts = (input.contexts ?? [])
      .map((value) => value.trim())
      .filter(Boolean);
    if (!contexts.length) {
      return [];
    }

    const ranked = await this.rerank(input.question, contexts);
    const targetCount = Math.min(5, Math.max(3, ranked.length));
    return ranked.slice(0, targetCount);
  }

  private async generateAnswer(
    input: AskInput,
    sourceChunks: string[],
  ): Promise<ProviderCallResult> {
    const { provider } = providerHeaders();
    const model = chooseModel(input);
    const OpenRouterClient = OpenRouter as unknown as new (
      options: Record<string, unknown>,
    ) => {
      chat: {
        send: (payload: Record<string, unknown>) => Promise<unknown>;
      };
    };
    const client = new OpenRouterClient({
      apiKey: provider.apiKey,
      baseURL: provider.baseUrl,
      httpReferer: env.appUrl || "http://localhost",
      appTitle: "Right Answer",
    });

    const systemPrompt = buildSystemPrompt(
      input,
      sourceChunks.join("\n\n"),
      sourceChunks.length,
    );
    const messages: ChatPromptMessage[] = [
      { role: "system", content: systemPrompt },
      ...(input.history ?? []).slice(-18),
      { role: "user", content: input.question },
    ];

    const response = await client.chat.send({
      model,
      messages,
      stream: false,
      temperature:
        input.temperature ?? (input.reasoningLevel === "high" ? 0.35 : 0.25),
      max_tokens:
        input.maxTokens ??
        (input.richAnswer
          ? 6000
          : input.responseLength === "large"
            ? 4096
            : 2048),
      ...(input.jsonMode ? { response_format: { type: "json_object" } } : {}),
    });

    const content = parseChatContent(response);
    if (!content) {
      throw new AppError(
        502,
        "The AI provider returned an empty answer",
        "EMPTY_AI_RESPONSE",
      );
    }

    const inputTokens = estimateTokens(JSON.stringify(messages));
    const outputTokens = estimateTokens(content);

    return {
      content,
      model,
      provider: provider.name,
      inputTokens,
      outputTokens,
    };
  }

  private keywordRerank(question: string, documents: string[]) {
    const tokens = new Set(
      normalizeQuestion(question)
        .split(" ")
        .filter((token) => token.length > 2),
    );
    return [...documents].sort((a, b) => {
      const score = (doc: string) =>
        normalizeQuestion(doc)
          .split(" ")
          .reduce((sum, token) => sum + (tokens.has(token) ? 1 : 0), 0);
      return score(b) - score(a);
    });
  }
}

export const aiService = new AiService();
