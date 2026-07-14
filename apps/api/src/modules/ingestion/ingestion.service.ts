import { createHash } from "node:crypto";

import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { APPROVED_TEXTBOOK_SOURCE_DOMAINS, DEFAULT_EMBEDDING_MODEL } from "@right-answer/config";
import { buildTextbookStorageKey } from "@right-answer/storage";
import pdf from "pdf-parse";

import { EmbeddingService } from "../common/embedding.service";
import { PrismaService } from "../common/prisma.service";
import { StorageService } from "../common/storage.service";

@Injectable()
export class IngestionService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    private readonly embedding: EmbeddingService,
  ) {}

  async listTextbooks() {
    return this.prisma.client.textbook.findMany({
      include: {
        subject: true,
        versions: {
          orderBy: { createdAt: "desc" },
        },
      },
      orderBy: {
        createdAt: "desc",
      },
    });
  }

  async listIngestionJobs() {
    return this.prisma.client.ingestionJob.findMany({
      include: {
        textbookVersion: true,
      },
      orderBy: {
        updatedAt: "desc",
      },
    });
  }

  async getIngestionJob(jobId: string) {
    const job = await this.prisma.client.ingestionJob.findUnique({
      where: { id: jobId },
      include: {
        textbookVersion: true,
      },
    });

    if (!job) {
      throw new NotFoundException("Ingestion job not found.");
    }

    return job;
  }

  async retryIngestionJob(jobId: string) {
    const job = await this.getIngestionJob(jobId);
    if (!job.textbookVersionId) {
      throw new BadRequestException("This job is not attached to a textbook version.");
    }

    const version = await this.prisma.client.textbookVersion.findUnique({
      where: { id: job.textbookVersionId },
      include: {
        textbook: {
          include: {
            subject: true,
          },
        },
      },
    });

    if (!version) {
      throw new NotFoundException("Textbook version not found.");
    }

    const rawPath = version.storagePath;
    const buffer = await this.storage.adapter.get(rawPath);

    return this.ingestPdfBuffer({
      buffer,
      subjectCode: version.textbook.subject.code,
      medium: version.textbook.medium,
      versionLabel: version.versionLabel,
      academicYear: version.academicYear ?? undefined,
      title: version.textbook.title,
      sourceUrl: version.sourceUrl ?? undefined,
      sourceType: version.sourceType ?? undefined,
      sourceDomain: version.sourceDomain ?? undefined,
      existingVersionId: version.id,
    });
  }

  async downloadAndIngest(params: {
    sourceUrl: string;
    subjectCode: string;
    medium: "en" | "ml";
    versionLabel: string;
    academicYear?: string;
    title?: string;
  }) {
    const url = new URL(params.sourceUrl);
    if (!APPROVED_TEXTBOOK_SOURCE_DOMAINS.includes(url.hostname as never)) {
      throw new BadRequestException("Source domain is not allowlisted for automated download.");
    }

    const response = await fetch(params.sourceUrl);
    if (!response.ok) {
      throw new BadRequestException(`Failed to download textbook: ${response.status}`);
    }

    const buffer = Buffer.from(await response.arrayBuffer());

    return this.ingestPdfBuffer({
      ...params,
      buffer,
      sourceType: "official_download",
      sourceDomain: url.hostname,
    });
  }

  async ingestPdfBuffer(params: {
    buffer: Buffer;
    subjectCode: string;
    medium: "en" | "ml";
    versionLabel: string;
    academicYear?: string;
    title?: string;
    sourceUrl?: string;
    sourceType?: string;
    sourceDomain?: string;
    existingVersionId?: string;
  }) {
    const subject = await this.prisma.client.subject.findFirst({
      where: { code: params.subjectCode },
    });

    if (!subject) {
      throw new BadRequestException(`Unknown subject code: ${params.subjectCode}`);
    }

    const checksum = createHash("sha256").update(params.buffer).digest("hex");

    const textbook =
      (await this.prisma.client.textbook.findFirst({
        where: {
          subjectId: subject.id,
          medium: params.medium,
        },
      })) ??
      (await this.prisma.client.textbook.create({
        data: {
          subjectId: subject.id,
          title: params.title ?? `${subject.name} Textbook`,
          medium: params.medium,
          classLevel: 10,
          syllabus: "Kerala SSLC",
          publisher: "Kerala SCERT",
        },
      }));

    const rawStorageKey = buildTextbookStorageKey({
      syllabus: "sslc",
      subjectSlug: params.subjectCode,
      medium: params.medium,
      versionLabel: params.versionLabel,
      kind: "raw",
      fileName: "source.pdf",
    });

    await this.storage.adapter.put(rawStorageKey, params.buffer);
    await this.storage.adapter.put(
      buildTextbookStorageKey({
        syllabus: "sslc",
        subjectSlug: params.subjectCode,
        medium: params.medium,
        versionLabel: params.versionLabel,
        kind: "raw",
        fileName: "source.meta.json",
      }),
      JSON.stringify(
        {
          checksumSha256: checksum,
          sourceUrl: params.sourceUrl ?? null,
          sourceType: params.sourceType ?? "manual_upload",
          sourceDomain: params.sourceDomain ?? null,
          downloadedAt: new Date().toISOString(),
        },
        null,
        2,
      ),
    );

    const version =
      (params.existingVersionId
        ? await this.prisma.client.textbookVersion.update({
            where: { id: params.existingVersionId },
            data: {
              checksumSha256: checksum,
              storagePath: rawStorageKey,
              status: "processing",
            },
          })
        : await this.prisma.client.textbookVersion.create({
            data: {
              textbookId: textbook.id,
              versionLabel: params.versionLabel,
              academicYear: params.academicYear,
              sourceUrl: params.sourceUrl,
              sourceType: params.sourceType ?? "manual_upload",
              sourceDomain: params.sourceDomain,
              checksumSha256: checksum,
              storagePath: rawStorageKey,
              status: "processing",
              downloadedAt: new Date(),
            },
          })) ??
      (await this.prisma.client.textbookVersion.findFirst({
        where: {
          textbookId: textbook.id,
          checksumSha256: checksum,
        },
      }));

    const job = await this.prisma.client.ingestionJob.create({
      data: {
        textbookId: textbook.id,
        textbookVersionId: version.id,
        status: "running",
        stage: "downloaded",
      },
    });

    const parsed = await pdf(params.buffer);
    const pageTexts = parsed.text.split(/\f+/).filter((block) => block.trim().length > 0);
    const fallbackPages = pageTexts.length ? pageTexts : [parsed.text];

    await this.prisma.client.page.deleteMany({
      where: { textbookVersionId: version.id },
    });
    await this.prisma.client.chapter.deleteMany({
      where: { textbookVersionId: version.id },
    });

    const chapter = await this.prisma.client.chapter.create({
      data: {
        textbookVersionId: version.id,
        chapterNumber: 1,
        title: params.title ?? `${subject.name} Imported Chapter`,
        startPage: 1,
        endPage: fallbackPages.length,
      },
    });

    const processedManifest = {
      textbookVersionId: version.id,
      subjectCode: params.subjectCode,
      medium: params.medium,
      versionLabel: params.versionLabel,
      pageCount: fallbackPages.length,
      checksumSha256: checksum,
      chunkingVersion: "v1",
      embeddingVersion: "v1",
      approved: true,
      createdAt: new Date().toISOString(),
    };

    await this.storage.adapter.put(
      buildTextbookStorageKey({
        syllabus: "sslc",
        subjectSlug: params.subjectCode,
        medium: params.medium,
        versionLabel: params.versionLabel,
        kind: "processed",
        fileName: "manifest.json",
      }),
      JSON.stringify(processedManifest, null, 2),
    );

    const contentUnits: { id: string; normalizedText: string }[] = [];

    for (const [index, pageText] of fallbackPages.entries()) {
      const page = await this.prisma.client.page.create({
        data: {
          textbookVersionId: version.id,
          chapterId: chapter.id,
          pageNumber: index + 1,
          rawText: pageText,
          normalizedText: this.embedding.normalizeText(pageText),
          ocrUsed: false,
          parseConfidence: parsed.text.trim().length ? 0.9 : 0.2,
          storagePath: buildTextbookStorageKey({
            syllabus: "sslc",
            subjectSlug: params.subjectCode,
            medium: params.medium,
            versionLabel: params.versionLabel,
            kind: "processed",
            fileName: `pages/${String(index + 1).padStart(3, "0")}.json`,
          }),
        },
      });

      await this.storage.adapter.put(
        page.storagePath,
        JSON.stringify(
          {
            pageNumber: page.pageNumber,
            text: pageText,
            warnings: parsed.text.trim().length ? [] : ["low_text_signal"],
          },
          null,
          2,
        ),
      );

      const paragraphs = pageText
        .split(/\n{2,}/)
        .map((paragraph) => paragraph.trim())
        .filter((paragraph) => paragraph.length > 30);

      for (const paragraph of paragraphs) {
        const normalized = this.embedding.normalizeText(paragraph);
        const contentUnit = await this.prisma.client.contentUnit.create({
          data: {
            pageId: page.id,
            chapterId: chapter.id,
            contentType:
              paragraph.toLowerCase().startsWith("definition") || paragraph.toLowerCase().includes(" is ")
                ? "paragraph"
                : "paragraph",
            text: paragraph,
            normalizedText: normalized,
            language: params.medium === "ml" ? "ml" : "en",
            keywords: normalized.split(" ").slice(0, 8),
            contentHash: createHash("sha256").update(`${version.id}:${page.id}:${paragraph}`).digest("hex"),
            metadata: {
              pageNumber: page.pageNumber,
              chapterTitle: chapter.title,
            },
          },
        });

        contentUnits.push({
          id: contentUnit.id,
          normalizedText: normalized,
        });

        const values = await this.embedding.embedText(normalized, "document");
        const embedding = await this.prisma.client.embedding.create({
          data: {
            contentUnitId: contentUnit.id,
            embeddingModel: DEFAULT_EMBEDDING_MODEL,
            embeddingVersion: "v1",
            embeddingValues: values,
            contentHash: contentUnit.contentHash,
          },
        });

        try {
          await this.prisma.client.$executeRawUnsafe(
            `UPDATE "Embedding" SET "embedding_vector" = $1::vector WHERE id = $2::uuid`,
            this.embedding.toVectorLiteral(values),
            embedding.id,
          );
        } catch {
          // Local plain-Postgres mode stores embedding arrays in JSON only.
        }
      }
    }

    await this.storage.adapter.put(
      buildTextbookStorageKey({
        syllabus: "sslc",
        subjectSlug: params.subjectCode,
        medium: params.medium,
        versionLabel: params.versionLabel,
        kind: "processed",
        fileName: "textbook.json",
      }),
      JSON.stringify(
        {
          textbookVersionId: version.id,
          chapter: {
            id: chapter.id,
            chapterNumber: chapter.chapterNumber,
            title: chapter.title,
          },
          contentUnitIds: contentUnits.map((unit) => unit.id),
        },
        null,
        2,
      ),
    );

    await this.prisma.client.textbookVersion.updateMany({
      where: {
        textbookId: textbook.id,
        id: { not: version.id },
      },
      data: {
        isActive: false,
      },
    });

    const publishedVersion = await this.prisma.client.textbookVersion.update({
      where: { id: version.id },
      data: {
        status: "published",
        isActive: true,
      },
    });

    await this.prisma.client.ingestionJob.update({
      where: { id: job.id },
      data: {
        status: "completed",
        stage: "indexed",
        metrics: {
          pageCount: fallbackPages.length,
          contentUnitCount: contentUnits.length,
        },
      },
    });

    return {
      jobId: job.id,
      textbookVersion: publishedVersion,
      pageCount: fallbackPages.length,
      contentUnitCount: contentUnits.length,
    };
  }
}
