import { Injectable } from "@nestjs/common";

import { PrismaService } from "../common/prisma.service";

@Injectable()
export class EvaluationService {
  constructor(private readonly prisma: PrismaService) {}

  async summary() {
    const [retrievalCount, cachedCount, modelCallCount] = await Promise.all([
      this.prisma.client.retrievalLog.count(),
      this.prisma.client.answerCache.count(),
      this.prisma.client.modelCall.count(),
    ]);

    return {
      retrievalCount,
      cachedCount,
      modelCallCount,
    };
  }
}
