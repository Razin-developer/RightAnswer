import { Injectable, NotFoundException } from "@nestjs/common";

import { PrismaService } from "../common/prisma.service";

@Injectable()
export class ContentService {
  constructor(private readonly prisma: PrismaService) {}

  async getSubjects() {
    return this.prisma.client.subject.findMany({
      where: { active: true },
      orderBy: { name: "asc" },
      select: {
        id: true,
        name: true,
        code: true,
      },
    });
  }

  async getChapters(subjectId: string) {
    const textbook = await this.prisma.client.textbook.findFirst({
      where: {
        subjectId,
        medium: "en",
      },
      include: {
        versions: {
          where: { isActive: true },
          include: {
            chapters: {
              orderBy: {
                chapterNumber: "asc",
              },
            },
          },
          take: 1,
        },
      },
    });

    return textbook?.versions[0]?.chapters ?? [];
  }

  async getChapter(chapterId: string) {
    const chapter = await this.prisma.client.chapter.findUnique({
      where: { id: chapterId },
      include: {
        pages: true,
        contentUnits: {
          take: 20,
          orderBy: { createdAt: "asc" },
        },
      },
    });

    if (!chapter) {
      throw new NotFoundException("Chapter not found.");
    }

    return chapter;
  }

  async getRevisionBundle(chapterId: string) {
    const chapter = await this.getChapter(chapterId);
    const keyPoints = chapter.contentUnits
      .filter((unit) => unit.contentType === "definition" || unit.contentType === "summary")
      .map((unit) => unit.text);

    return {
      chapter: {
        id: chapter.id,
        chapterNumber: chapter.chapterNumber,
        title: chapter.title,
      },
      keyPoints,
      pages: chapter.pages.map((page) => ({
        id: page.id,
        pageNumber: page.pageNumber,
      })),
    };
  }
}
