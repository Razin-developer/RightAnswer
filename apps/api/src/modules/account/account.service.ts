import { Injectable, NotFoundException } from "@nestjs/common";

import { BillingService } from "../billing/billing.service";
import { PrismaService } from "../common/prisma.service";

@Injectable()
export class AccountService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly billing: BillingService,
  ) {}

  async me(userId: string) {
    const user = await this.prisma.client.user.findUnique({
      where: { id: userId },
      include: { profile: true },
    });
    if (!user) {
      throw new NotFoundException("User not found.");
    }

    return {
      id: user.id,
      email: user.email,
      role: user.role,
      profile: user.profile,
      planCode: await this.billing.getUserPlan(userId),
    };
  }

  async updateProfile(userId: string, body: { preferredLanguage?: "en" | "ml"; schoolName?: string }) {
    const user = await this.prisma.client.user.findUnique({
      where: { id: userId },
      include: { profile: true },
    });
    if (!user?.profile) {
      throw new NotFoundException("User profile not found.");
    }

    return this.prisma.client.userProfile.update({
      where: { userId },
      data: {
        preferredLanguage: body.preferredLanguage,
        schoolName: body.schoolName,
      },
    });
  }

  async answerHistory(userId: string) {
    return this.prisma.client.retrievalLog.findMany({
      where: { userId },
      orderBy: { createdAt: "desc" },
      take: 20,
    });
  }

  async addFeedback(userId: string, body: { answerCacheId: string; rating: number; issueType?: string; comment?: string }) {
    const feedback = await this.prisma.client.feedback.create({
      data: {
        userId,
        answerCacheId: body.answerCacheId,
        rating: body.rating,
        issueType: body.issueType,
        feedbackText: body.comment,
      },
    });

    const data = body.rating >= 4
      ? { positiveFeedbackCount: { increment: 1 } }
      : { negativeFeedbackCount: { increment: 1 } };

    await this.prisma.client.answerCache.update({
      where: { id: body.answerCacheId },
      data,
    });

    return feedback;
  }

  listFeedback() {
    return this.prisma.client.feedback.findMany({
      include: {
        user: true,
        answerCache: true,
      },
      orderBy: { createdAt: "desc" },
    });
  }

  async subscription(userId: string) {
    const planCode = await this.billing.getUserPlan(userId);
    const subscription = await this.prisma.client.subscription.findFirst({
      where: {
        userId,
        status: "active",
      },
      orderBy: {
        startsAt: "desc",
      },
    });

    return {
      planCode,
      subscription,
    };
  }

  async usage(userId: string) {
    const startOfDay = new Date();
    startOfDay.setUTCHours(0, 0, 0, 0);
    const planCode = await this.billing.getUserPlan(userId);

    const events = await this.prisma.client.usageEvent.groupBy({
      by: ["eventType"],
      where: {
        userId,
        createdAt: {
          gte: startOfDay,
        },
      },
      _count: {
        eventType: true,
      },
    });

    return {
      planCode,
      usage: events,
      limits: await this.billing.getPlanLimits(planCode),
    };
  }

  usageLimits() {
    return this.prisma.client.usageLimit.findMany({
      orderBy: { priorityLevel: "asc" },
    });
  }

  checkout(planCode: string) {
    return {
      planCode,
      checkoutUrl: null,
      status: "pending_provider_configuration",
      note: "Payment gateway integration should be configured with production billing credentials.",
    };
  }
}
