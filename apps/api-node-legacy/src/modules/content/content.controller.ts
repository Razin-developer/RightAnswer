import { Controller, Get, Param } from "@nestjs/common";

import { ok } from "../common/response.util";

import { ContentService } from "./content.service";

@Controller()
export class ContentController {
  constructor(private readonly contentService: ContentService) {}

  @Get("subjects")
  async subjects() {
    return ok(await this.contentService.getSubjects());
  }

  @Get("subjects/:subjectId/chapters")
  async chapters(@Param("subjectId") subjectId: string) {
    return ok(await this.contentService.getChapters(subjectId));
  }

  @Get("chapters/:chapterId")
  async chapter(@Param("chapterId") chapterId: string) {
    return ok(await this.contentService.getChapter(chapterId));
  }

  @Get("chapters/:chapterId/revision")
  async revision(@Param("chapterId") chapterId: string) {
    return ok(await this.contentService.getRevisionBundle(chapterId));
  }
}
