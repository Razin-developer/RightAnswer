import { Injectable, NotFoundException } from "@nestjs/common";
import { Prisma } from "@prisma/client";

import { IngestionService } from "../ingestion/ingestion.service";
import { PrismaService } from "../common/prisma.service";

import type {
  DownloadTextbookDto,
  UpdateContentUnitDto,
  UpdateExamModeDto,
  UpdateModelProviderDto,
} from "./admin.dto";

@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly ingestion: IngestionService,
  ) {}

  listTextbooks() {
    return this.ingestion.listTextbooks();
  }

  listIngestionJobs() {
    return this.ingestion.listIngestionJobs();
  }

  getIngestionJob(jobId: string) {
    return this.ingestion.getIngestionJob(jobId);
  }

  retryIngestionJob(jobId: string) {
    return this.ingestion.retryIngestionJob(jobId);
  }

  async downloadTextbook(dto: DownloadTextbookDto) {
    return this.ingestion.downloadAndIngest(dto);
  }

  async uploadTextbook(params: {
    buffer: Buffer;
    subjectCode: string;
    medium: "en" | "ml";
    versionLabel: string;
    academicYear?: string;
    title?: string;
    sourceUrl?: string;
  }) {
    return this.ingestion.ingestPdfBuffer({
      buffer: params.buffer,
      subjectCode: params.subjectCode,
      medium: params.medium,
      versionLabel: params.versionLabel,
      academicYear: params.academicYear,
      title: params.title,
      sourceUrl: params.sourceUrl,
      sourceType: "manual_upload",
      sourceDomain: params.sourceUrl ? new URL(params.sourceUrl).hostname : undefined,
    });
  }

  async listContentUnits(filters: {
    subjectId?: string;
    chapterId?: string;
    contentType?: string;
    page?: string;
  }) {
    return this.prisma.client.contentUnit.findMany({
      where: {
        chapterId: filters.chapterId,
        contentType: filters.contentType as never,
        page: filters.page
          ? {
              pageNumber: Number(filters.page),
            }
          : undefined,
        chapter: filters.subjectId
          ? {
              textbookVersion: {
                textbook: {
                  subjectId: filters.subjectId,
                },
              },
            }
          : undefined,
      },
      include: {
        page: true,
        chapter: true,
      },
      orderBy: {
        createdAt: "asc",
      },
    });
  }

  async getContentUnit(id: string) {
    const unit = await this.prisma.client.contentUnit.findUnique({
      where: { id },
      include: {
        page: true,
        chapter: true,
        assets: true,
      },
    });

    if (!unit) {
      throw new NotFoundException("Content unit not found.");
    }

    return unit;
  }

  async updateContentUnit(id: string, dto: UpdateContentUnitDto) {
    return this.prisma.client.contentUnit.update({
      where: { id },
      data: {
        text: dto.text,
        normalizedText: dto.text ?? undefined,
        metadata: (dto.metadata ?? undefined) as Prisma.InputJsonValue | undefined,
      },
    });
  }

  async getAsset(id: string) {
    const asset = await this.prisma.client.textbookAsset.findUnique({
      where: { id },
      include: {
        tableRecord: true,
        graphRecord: true,
        diagramRecord: true,
      },
    });

    if (!asset) {
      throw new NotFoundException("Asset not found.");
    }

    return asset;
  }

  listModelProviders() {
    return this.prisma.client.modelProvider.findMany({
      orderBy: { priority: "asc" },
    });
  }

  updateModelProvider(id: string, dto: UpdateModelProviderDto) {
    return this.prisma.client.modelProvider.update({
      where: { id },
      data: dto,
    });
  }

  async getExamMode() {
    return this.prisma.client.examModeSetting.findFirst({
      orderBy: { updatedAt: "desc" },
    });
  }

  async updateExamMode(dto: UpdateExamModeDto) {
    const current = await this.getExamMode();
    if (!current) {
      return this.prisma.client.examModeSetting.create({
        data: {
          enabled: dto.enabled,
          freePremiumDisabled: dto.freePremiumDisabled ?? true,
          shortAnswerDefault: dto.shortAnswerDefault ?? true,
          trafficMode: dto.enabled ? "exam" : "normal",
        },
      });
    }

    return this.prisma.client.examModeSetting.update({
      where: { id: current.id },
      data: {
        enabled: dto.enabled,
        freePremiumDisabled: dto.freePremiumDisabled ?? current.freePremiumDisabled,
        shortAnswerDefault: dto.shortAnswerDefault ?? current.shortAnswerDefault,
        trafficMode: dto.enabled ? "exam" : "normal",
      },
    });
  }

  async reindex(textbookVersionId: string, initiatedByUserId: string) {
    const job = await this.prisma.client.adminJob.create({
      data: {
        jobType: "reindex_textbook",
        initiatedByUserId,
        status: "completed",
        payload: { textbookVersionId },
        startedAt: new Date(),
        finishedAt: new Date(),
      },
    });

    await this.prisma.client.queueJob.create({
      data: {
        adminJobId: job.id,
        queueName: "embedding_jobs",
        jobReference: textbookVersionId,
        status: "completed",
        priority: 5,
      },
    });

    return job;
  }
}
