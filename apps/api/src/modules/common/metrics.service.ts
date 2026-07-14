import { Injectable, Logger } from "@nestjs/common";
import { Prisma } from "@prisma/client";

import { PrismaService } from "./prisma.service";

@Injectable()
export class MetricsService {
  private readonly logger = new Logger(MetricsService.name);

  constructor(private readonly prisma: PrismaService) {}

  async logRetrieval(params: {
    requestId: string;
    userId?: string;
    chapterId?: string;
    question: string;
    filters: Record<string, unknown>;
    retrievedUnitIds: string[];
    scores: unknown[];
    confidence: number;
  }) {
    await this.prisma.client.retrievalLog.create({
      data: {
        requestId: params.requestId,
        userId: params.userId,
        chapterId: params.chapterId,
        question: params.question,
        filters: params.filters as Prisma.InputJsonValue,
        retrievedUnitIds: params.retrievedUnitIds,
        scores: params.scores as Prisma.InputJsonValue,
        confidence: params.confidence,
      },
    });
  }

  logMessage(message: string) {
    this.logger.log(message);
  }
}
