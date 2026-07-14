import { Injectable } from "@nestjs/common";

import { BillingService } from "../billing/billing.service";
import { PrismaService } from "../common/prisma.service";

import type { GenerateWorksheetDto, VerifyAnswerDto } from "./teacher.dto";

@Injectable()
export class TeacherService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly billing: BillingService,
  ) {}

  async verifyAnswer(teacherUserId: string, dto: VerifyAnswerDto) {
    const entry = await this.prisma.client.teacherVerifiedAnswer.create({
      data: {
        teacherUserId,
        answerCacheId: dto.answerCacheId,
        status: dto.status,
        notes: dto.notes,
      },
    });

    await this.prisma.client.answerCache.update({
      where: { id: dto.answerCacheId },
      data: {
        verificationStatus: dto.status === "approved" ? "gold" : dto.status === "flagged" ? "unsafe" : "bronze",
      },
    });

    return entry;
  }

  async generateWorksheet(userId: string, dto: GenerateWorksheetDto) {
    const planCode = await this.billing.getUserPlan(userId);
    await this.billing.enforceRequestRateLimit({
      userId,
      planCode,
      requestType: "worksheet_generation",
    });

    const chapters = await this.prisma.client.chapter.findMany({
      where: {
        id: {
          in: dto.chapterIds,
        },
      },
      include: {
        contentUnits: {
          take: 10,
        },
      },
      orderBy: {
        chapterNumber: "asc",
      },
    });

    const questions = chapters.flatMap((chapter) =>
      chapter.contentUnits.slice(0, 3).map((unit, index) => ({
        chapterTitle: chapter.title,
        marks: [1, 3, 5][index] ?? 3,
        question: `From ${chapter.title}: Explain ${unit.text.split(" ").slice(0, 6).join(" ")}...`,
      })),
    );

    await this.billing.recordUsage({
      userId,
      eventType: "worksheet_generation",
      metadata: { chapterCount: dto.chapterIds.length },
    });

    return {
      title: "Teacher Worksheet",
      questions,
    };
  }

  async commonDoubts(subjectId?: string, chapterId?: string) {
    const grouped = await this.prisma.client.answerCache.groupBy({
      by: ["question", "chapterId", "subjectId"],
      where: {
        subjectId: subjectId ?? undefined,
        chapterId: chapterId ?? undefined,
      },
      _count: {
        question: true,
      },
      orderBy: {
        _count: {
          question: "desc",
        },
      },
      take: 10,
    });

    return grouped.map((row) => ({
      question: row.question,
      chapterId: row.chapterId,
      subjectId: row.subjectId,
      count: row._count.question,
    }));
  }
}
