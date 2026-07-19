import { ForbiddenException, HttpException, HttpStatus, Injectable } from "@nestjs/common";
import { Prisma } from "@prisma/client";

import type { UsageEventType } from "@prisma/client";

import { CacheService } from "../common/cache.service";
import { PrismaService } from "../common/prisma.service";

@Injectable()
export class BillingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly cache: CacheService,
  ) {}

  async getUserPlan(userId: string) {
    const subscription = await this.prisma.client.subscription.findFirst({
      where: {
        userId,
        status: "active",
      },
      orderBy: {
        startsAt: "desc",
      },
    });

    return subscription?.planCode ?? "free";
  }

  async getPlanLimits(planCode: string) {
    const limits = await this.prisma.client.usageLimit.findUnique({
      where: { planCode },
    });

    if (!limits) {
      throw new ForbiddenException(`No usage limit profile found for plan ${planCode}.`);
    }

    return limits;
  }

  async getExamMode() {
    return this.prisma.client.examModeSetting.findFirst({
      orderBy: { updatedAt: "desc" },
    });
  }

  async enforceRequestRateLimit(params: {
    userId: string;
    planCode: string;
    requestType: "cached_answer" | "live_answer" | "premium_fallback" | "worksheet_generation";
  }) {
    const limits = await this.getPlanLimits(params.planCode);
    const examMode = await this.getExamMode();
    const minuteBucket = Math.floor(Date.now() / 60000);
    const rpmKey = `rate:${params.userId}:${params.requestType}:${minuteBucket}`;

    const minuteCount = await this.cache.increment(rpmKey, 120);
    const rpmLimit =
      params.requestType === "cached_answer"
        ? Math.max(20, Math.floor(limits.cachedDailyLimit / 10))
        : Math.max(4, Math.floor(limits.liveDailyLimit / 10));

    if (minuteCount > rpmLimit) {
      throw new HttpException(
        "Too many requests in a short time. Please try again.",
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }

    const startOfDay = new Date();
    startOfDay.setUTCHours(0, 0, 0, 0);

    const usageCount = await this.prisma.client.usageEvent.count({
      where: {
        userId: params.userId,
        eventType: params.requestType as UsageEventType,
        createdAt: {
          gte: startOfDay,
        },
      },
    });

    let dailyLimit = limits.cachedDailyLimit;
    if (params.requestType === "live_answer") {
      dailyLimit = limits.liveDailyLimit;
    }
    if (params.requestType === "premium_fallback") {
      dailyLimit = limits.premiumDailyLimit;
    }
    if (params.requestType === "worksheet_generation") {
      dailyLimit = limits.worksheetGenerationLimit;
    }

    if (examMode?.enabled && params.planCode === "free" && params.requestType === "premium_fallback") {
      throw new ForbiddenException("Premium fallback is disabled for free users during exam mode.");
    }

    if (usageCount >= dailyLimit) {
      throw new HttpException(
        "Daily usage limit reached for this request type.",
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }

  async recordUsage(params: {
    userId: string;
    eventType: UsageEventType;
    requestId?: string;
    units?: number;
    metadata?: Record<string, unknown>;
  }) {
    await this.prisma.client.usageEvent.create({
      data: {
        userId: params.userId,
        eventType: params.eventType,
        requestId: params.requestId,
        units: params.units ?? 1,
        metadata: (params.metadata ?? {}) as Prisma.InputJsonValue,
      },
    });
  }
}
