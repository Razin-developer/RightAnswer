import { randomUUID } from "node:crypto";

import { Injectable } from "@nestjs/common";
import type { AnswerCache, ContentUnit } from "@prisma/client";
import type { AnswerPayload, Citation } from "@right-answer/types";

import { BillingService } from "../billing/billing.service";
import { CacheService } from "../common/cache.service";
import { EmbeddingService } from "../common/embedding.service";
import { MetricsService } from "../common/metrics.service";
import { PrismaService } from "../common/prisma.service";
import {
  detectContentPreference,
  detectDifficulty,
  sanitizeQuestion,
  toQuestionTokens,
} from "../common/query.util";
import { ContentService } from "../content/content.service";
import { ModelGatewayService } from "../providers/model-gateway.service";

import type { AskQuestionDto } from "./ask.dto";

interface RetrievalCandidate {
  id: string;
  text: string;
  contentType: string;
  pageNumber: number;
  chapterId: string;
  chapterNumber: number;
  chapterTitle: string;
  keywordScore: number;
  vectorScore: number;
  metadataMatchScore: number;
  proximityScore: number;
  historicalSuccessScore: number;
  finalScore: number;
}

@Injectable()
export class AskService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly cache: CacheService,
    private readonly embedding: EmbeddingService,
    private readonly billing: BillingService,
    private readonly metrics: MetricsService,
    private readonly modelGateway: ModelGatewayService,
    private readonly contentService: ContentService,
  ) {}

  async ask(userId: string, dto: AskQuestionDto): Promise<AnswerPayload> {
    const requestId = randomUUID();
    const sanitizedQuestion = sanitizeQuestion(dto.question);
    const normalizedQuestion = this.embedding.normalizeText(sanitizedQuestion);
    const planCode = await this.billing.getUserPlan(userId);
    const examMode = await this.billing.getExamMode();
    const trafficMode = examMode?.enabled ? "exam" : "normal";
    const exactKey = this.buildExactKey(dto, normalizedQuestion);

    const exactHit = await this.lookupExactCache(exactKey);
    if (exactHit) {
      await this.billing.enforceRequestRateLimit({
        userId,
        planCode,
        requestType: "cached_answer",
      });
      await this.billing.recordUsage({
        userId,
        eventType: "cached_answer",
        requestId,
        metadata: { source: "exact_cache" },
      });
      return this.answerCacheToPayload(exactHit, "exact_cache");
    }

    const queryEmbedding = await this.embedding.embedText(normalizedQuestion, "query");
    const semanticHit = await this.lookupSemanticCache(dto, queryEmbedding);
    if (semanticHit && semanticHit.similarity >= 0.92) {
      await this.billing.enforceRequestRateLimit({
        userId,
        planCode,
        requestType: "cached_answer",
      });
      await this.billing.recordUsage({
        userId,
        eventType: "cached_answer",
        requestId,
        metadata: { source: "semantic_cache", similarity: semanticHit.similarity },
      });
      return this.answerCacheToPayload(semanticHit.answerCache, "semantic_cache");
    }

    await this.billing.enforceRequestRateLimit({
      userId,
      planCode,
      requestType: "live_answer",
    });

    const retrievalKey = `retrieval:${dto.subjectId ?? "all"}:${dto.chapterId ?? "all"}:${normalizedQuestion}`;
    let candidates = await this.cache.getJson<RetrievalCandidate[]>(retrievalKey);

    if (!candidates) {
      candidates = await this.hybridRetrieve({
        question: sanitizedQuestion,
        normalizedQuestion,
        subjectId: dto.subjectId ?? undefined,
        chapterId: dto.chapterId ?? undefined,
      });
      await this.cache.setJson(retrievalKey, candidates, 3600);
    }

    const confidence = this.computeConfidence(candidates);
    const topCandidates = candidates.slice(0, 5);
    const topUnits = await this.prisma.client.contentUnit.findMany({
      where: {
        id: {
          in: topCandidates.map((candidate) => candidate.id),
        },
      },
      include: {
        page: true,
        chapter: true,
      },
    });

    const citations = topUnits.slice(0, 3).map((unit) => this.unitToCitation(unit));
    const context = topUnits.map((unit) => unit.text).join(" ");
    const difficulty = detectDifficulty(sanitizedQuestion);
    const contentPreference = detectContentPreference(sanitizedQuestion);

    let answerText: string;
    let servedFrom = "hybrid_rag";
    let modelUsed: string | null = null;

    if (confidence >= 0.9 && contentPreference === "definition" && topUnits[0]) {
      answerText = topUnits[0].text;
      servedFrom = "template_answer";
      modelUsed = "template";
    } else {
      const generation = await this.modelGateway.generateGroundedAnswer({
        requestId,
        userId,
        planCode,
        language: dto.language,
        answerType: dto.answerType as never,
        question: sanitizedQuestion,
        context:
          context ||
          "The answer is not clearly present in the textbook. Provide the closest useful explanation and say that clearly.",
        citations,
        difficulty,
        trafficMode,
        allowPremiumFallback: planCode !== "free" && !examMode?.freePremiumDisabled,
      });

      answerText = generation.answerText;
      modelUsed = generation.modelUsed;
      servedFrom = generation.routeCode;
    }

    const answerCache = await this.persistAnswerCache({
      dto,
      normalizedQuestion,
      question: sanitizedQuestion,
      answerText,
      citations,
      confidence,
      sourceContentUnitIds: topUnits.map((unit) => unit.id),
      modelUsed,
      exactKey,
      queryEmbedding,
    });

    await this.metrics.logRetrieval({
      requestId,
      userId,
      chapterId: dto.chapterId ?? topCandidates[0]?.chapterId,
      question: sanitizedQuestion,
      filters: {
        subjectId: dto.subjectId ?? null,
        chapterId: dto.chapterId ?? null,
        answerType: dto.answerType,
      },
      retrievedUnitIds: topCandidates.map((candidate) => candidate.id),
      scores: topCandidates.map((candidate) => ({
        id: candidate.id,
        finalScore: candidate.finalScore,
        keywordScore: candidate.keywordScore,
        vectorScore: candidate.vectorScore,
      })),
      confidence,
    });

    await this.billing.recordUsage({
      userId,
      eventType: "live_answer",
      requestId,
      metadata: { servedFrom, modelUsed },
    });

    return this.answerCacheToPayload(answerCache, servedFrom);
  }

  private buildExactKey(dto: AskQuestionDto, normalizedQuestion: string) {
    return [
      normalizedQuestion,
      dto.language,
      dto.answerType,
      dto.subjectId ?? "",
      dto.chapterId ?? "",
    ].join("|");
  }

  private async lookupExactCache(exactKey: string) {
    const redisHit = await this.cache.getJson<AnswerCache>(`exact:${exactKey}`);
    if (redisHit) {
      return redisHit;
    }

    const hit = await this.prisma.client.exactCache.findUnique({
      where: { cacheKey: exactKey },
      include: { answerCache: true },
    });

    if (!hit) {
      return null;
    }

    await this.cache.setJson(`exact:${exactKey}`, hit.answerCache, 86400);
    return hit.answerCache;
  }

  private async lookupSemanticCache(dto: AskQuestionDto, queryEmbedding: number[]) {
    const candidates = await this.prisma.client.semanticCache.findMany({
      include: {
        answerCache: true,
      },
    });

    const filtered = candidates.filter((candidate) => {
      if (candidate.answerCache.language !== dto.language) return false;
      if (candidate.answerCache.answerFormat !== dto.answerType) return false;
      if (dto.subjectId && candidate.answerCache.subjectId !== dto.subjectId) return false;
      if (dto.chapterId && candidate.answerCache.chapterId !== dto.chapterId) return false;
      return true;
    });

    let best: { answerCache: AnswerCache; similarity: number } | null = null;

    for (const candidate of filtered) {
      const similarity = this.embedding.cosineSimilarity(
        candidate.questionEmbeddingValues as number[],
        queryEmbedding,
      );

      if (!best || similarity > best.similarity) {
        best = {
          answerCache: candidate.answerCache,
          similarity,
        };
      }
    }

    return best;
  }

  private async hybridRetrieve(params: {
    question: string;
    normalizedQuestion: string;
    subjectId?: string;
    chapterId?: string;
  }) {
    const tokens = toQuestionTokens(params.normalizedQuestion);
    const queryEmbedding = await this.embedding.embedText(params.normalizedQuestion, "query");
    const vectorLiteral = this.embedding.toVectorLiteral(queryEmbedding);
    const keywordQuery = tokens.join(" & ") || "textbook";

    const keywordRows = await this.prisma.client.$queryRawUnsafe<RetrievalCandidate[]>(
      `
      SELECT
        cu.id,
        cu.text,
        cu."content_type" as "contentType",
        p."page_number" as "pageNumber",
        ch.id as "chapterId",
        ch."chapter_number" as "chapterNumber",
        ch.title as "chapterTitle",
        COALESCE(ts_rank(to_tsvector('simple', cu."normalized_text"), to_tsquery('simple', $1)), 0) as "keywordScore",
        0 as "vectorScore",
        0 as "metadataMatchScore",
        0 as "proximityScore",
        0 as "historicalSuccessScore",
        0 as "finalScore"
      FROM "ContentUnit" cu
      INNER JOIN "Page" p ON p.id = cu."page_id"
      INNER JOIN "Chapter" ch ON ch.id = cu."chapter_id"
      INNER JOIN "TextbookVersion" tv ON tv.id = ch."textbook_version_id"
      INNER JOIN "Textbook" t ON t.id = tv."textbook_id"
      WHERE ($2::uuid IS NULL OR t."subject_id" = $2::uuid)
        AND ($3::uuid IS NULL OR ch.id = $3::uuid)
        AND tv."is_active" = true
      ORDER BY "keywordScore" DESC
      LIMIT 12
      `,
      keywordQuery,
      params.subjectId ?? null,
      params.chapterId ?? null,
    );

    let vectorRows: RetrievalCandidate[] = [];

    try {
      vectorRows = await this.prisma.client.$queryRawUnsafe<RetrievalCandidate[]>(
        `
        SELECT
          cu.id,
          cu.text,
          cu."content_type" as "contentType",
          p."page_number" as "pageNumber",
          ch.id as "chapterId",
          ch."chapter_number" as "chapterNumber",
          ch.title as "chapterTitle",
          0 as "keywordScore",
          (1 - (e."embedding_vector" <=> $1::vector)) as "vectorScore",
          0 as "metadataMatchScore",
          0 as "proximityScore",
          0 as "historicalSuccessScore",
          0 as "finalScore"
        FROM "Embedding" e
        INNER JOIN "ContentUnit" cu ON cu.id = e."content_unit_id"
        INNER JOIN "Page" p ON p.id = cu."page_id"
        INNER JOIN "Chapter" ch ON ch.id = cu."chapter_id"
        INNER JOIN "TextbookVersion" tv ON tv.id = ch."textbook_version_id"
        INNER JOIN "Textbook" t ON t.id = tv."textbook_id"
        WHERE ($2::uuid IS NULL OR t."subject_id" = $2::uuid)
          AND ($3::uuid IS NULL OR ch.id = $3::uuid)
          AND tv."is_active" = true
        ORDER BY e."embedding_vector" <=> $1::vector ASC
        LIMIT 12
        `,
        vectorLiteral,
        params.subjectId ?? null,
        params.chapterId ?? null,
      );
    } catch {
      const allEmbeddings = await this.prisma.client.embedding.findMany({
        include: {
          contentUnit: {
            include: {
              page: true,
              chapter: true,
            },
          },
        },
      });

      vectorRows = allEmbeddings
        .filter((embedding) => {
          if (params.chapterId && embedding.contentUnit.chapterId !== params.chapterId) return false;
          return true;
        })
        .map((embedding) => ({
          id: embedding.contentUnit.id,
          text: embedding.contentUnit.text,
          contentType: embedding.contentUnit.contentType,
          pageNumber: embedding.contentUnit.page.pageNumber,
          chapterId: embedding.contentUnit.chapter.id,
          chapterNumber: embedding.contentUnit.chapter.chapterNumber,
          chapterTitle: embedding.contentUnit.chapter.title,
          keywordScore: 0,
          vectorScore: this.embedding.cosineSimilarity(
            embedding.embeddingValues as number[],
            queryEmbedding,
          ),
          metadataMatchScore: 0,
          proximityScore: 0,
          historicalSuccessScore: 0,
          finalScore: 0,
        }))
        .sort((a, b) => b.vectorScore - a.vectorScore)
        .slice(0, 12);
    }

    const merged = new Map<string, RetrievalCandidate>();
    for (const candidate of [...keywordRows, ...vectorRows]) {
      const existing = merged.get(candidate.id);
      if (existing) {
        existing.keywordScore = Math.max(existing.keywordScore, Number(candidate.keywordScore));
        existing.vectorScore = Math.max(existing.vectorScore, Number(candidate.vectorScore));
      } else {
        merged.set(candidate.id, {
          ...candidate,
          keywordScore: Number(candidate.keywordScore),
          vectorScore: Number(candidate.vectorScore),
          metadataMatchScore: 0,
          proximityScore: 0.5,
          historicalSuccessScore: 0.4,
          finalScore: 0,
        });
      }
    }

    const preferredContent = detectContentPreference(params.question);

    return Array.from(merged.values())
      .map((candidate) => {
        candidate.metadataMatchScore =
          candidate.contentType === preferredContent || preferredContent === "paragraph" ? 1 : 0.5;
        candidate.finalScore =
          0.35 * candidate.keywordScore +
          0.35 * candidate.vectorScore +
          0.15 * candidate.metadataMatchScore +
          0.1 * candidate.proximityScore +
          0.05 * candidate.historicalSuccessScore;
        return candidate;
      })
      .sort((a, b) => b.finalScore - a.finalScore)
      .slice(0, 10);
  }

  private computeConfidence(candidates: RetrievalCandidate[]) {
    if (!candidates.length) {
      return 0.2;
    }

    const top = candidates[0];
    const next = candidates[1];
    const spread = Math.max(0, top.finalScore - (next?.finalScore ?? 0));

    return Math.min(
      0.99,
      0.3 * top.finalScore +
        0.2 * spread +
        0.2 * Math.min(1, candidates.length / 5) +
        0.15 * top.metadataMatchScore +
        0.15 * top.proximityScore,
    );
  }

  private unitToCitation(
    unit: ContentUnit & {
      page: { pageNumber: number };
      chapter: { title: string; chapterNumber: number };
    },
  ): Citation {
    return {
      chapterTitle: unit.chapter.title,
      chapterNumber: unit.chapter.chapterNumber,
      pageNumber: unit.page.pageNumber,
      contentUnitId: unit.id,
      excerpt: unit.text.slice(0, 180),
    };
  }

  private async persistAnswerCache(params: {
    dto: AskQuestionDto;
    normalizedQuestion: string;
    question: string;
    answerText: string;
    citations: Citation[];
    confidence: number;
    sourceContentUnitIds: string[];
    modelUsed: string | null;
    exactKey: string;
    queryEmbedding: number[];
  }) {
    const answerCache = await this.prisma.client.answerCache.create({
      data: {
        question: params.question,
        normalizedQuestion: params.normalizedQuestion,
        subjectId: params.dto.subjectId ?? null,
        chapterId: params.dto.chapterId ?? null,
        language: params.dto.language,
        answerFormat: params.dto.answerType,
        answerText: params.answerText,
        citations: params.citations as never,
        confidenceScore: params.confidence,
        sourceContentUnitIds: params.sourceContentUnitIds,
        modelUsed: params.modelUsed,
        cacheType: "answer",
        verificationStatus: params.confidence >= 0.9 ? "silver" : "bronze",
        usageCount: 0,
      },
    });

    const semanticEntry = await this.prisma.client.semanticCache.create({
      data: {
        questionText: params.question,
        normalizedQuestion: params.normalizedQuestion,
        answerCacheId: answerCache.id,
        similarityFloor: 0.85,
        questionEmbeddingValues: params.queryEmbedding,
      },
    });

    try {
      await this.prisma.client.$executeRawUnsafe(
        `UPDATE "SemanticCache" SET "question_embedding_vector" = $1::vector WHERE id = $2::uuid`,
        this.embedding.toVectorLiteral(params.queryEmbedding),
        semanticEntry.id,
      );
    } catch {
      // Local plain-Postgres mode stores embedding arrays in JSON only.
    }

    await this.prisma.client.exactCache.upsert({
      where: { cacheKey: params.exactKey },
      update: {
        answerCacheId: answerCache.id,
      },
      create: {
        cacheKey: params.exactKey,
        answerCacheId: answerCache.id,
      },
    });

    await this.cache.setJson(`exact:${params.exactKey}`, answerCache, 86400);
    return answerCache;
  }

  private answerCacheToPayload(answerCache: AnswerCache, servedFrom: string): AnswerPayload {
    return {
      answerText: answerCache.answerText,
      answerType: answerCache.answerFormat as never,
      language: answerCache.language as "en" | "ml",
      servedFrom,
      confidence: answerCache.confidenceScore,
      citations: answerCache.citations as unknown as Citation[],
      modelUsed: answerCache.modelUsed,
      verificationStatus: answerCache.verificationStatus as never,
    };
  }
}
