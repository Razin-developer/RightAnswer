import { Body, Controller, Get, Param, Patch, Post, Query, Req, UseGuards } from "@nestjs/common";
import type { FastifyRequest } from "fastify";

import { CurrentUser } from "../common/current-user.decorator";
import { JwtAuthGuard } from "../common/jwt-auth.guard";
import { ok } from "../common/response.util";
import { Roles } from "../common/roles.decorator";

import {
  DownloadTextbookDto,
  UpdateContentUnitDto,
  UpdateExamModeDto,
  UpdateModelProviderDto,
} from "./admin.dto";
import { AdminService } from "./admin.service";

@Controller()
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  @Get("textbooks")
  @UseGuards(JwtAuthGuard)
  @Roles("admin")
  async textbooks() {
    return ok(await this.adminService.listTextbooks());
  }

  @Post("textbooks/upload")
  @UseGuards(JwtAuthGuard)
  @Roles("admin")
  async uploadTextbook(@Req() request: FastifyRequest) {
    const file = await request.file();
    if (!file) {
      throw new Error("Missing PDF upload.");
    }

    const chunks: Buffer[] = [];
    for await (const chunk of file.file) {
      chunks.push(chunk);
    }

    const fields = file.fields as Record<string, { value: string }>;
    const buffer = Buffer.concat(chunks);

    return ok(
      await this.adminService.uploadTextbook({
        buffer,
        subjectCode: fields.subjectCode?.value,
        medium: (fields.medium?.value as "en" | "ml") ?? "en",
        versionLabel: fields.versionLabel?.value ?? "manual-v1",
        academicYear: fields.academicYear?.value,
        title: fields.title?.value,
        sourceUrl: fields.sourceUrl?.value,
      }),
    );
  }

  @Post("textbooks/download")
  @UseGuards(JwtAuthGuard)
  @Roles("admin")
  async downloadTextbook(@Body() dto: DownloadTextbookDto) {
    return ok(await this.adminService.downloadTextbook(dto));
  }

  @Get("ingestion-jobs")
  @UseGuards(JwtAuthGuard)
  @Roles("admin")
  async ingestionJobs() {
    return ok(await this.adminService.listIngestionJobs());
  }

  @Get("ingestion-jobs/:jobId")
  @UseGuards(JwtAuthGuard)
  @Roles("admin")
  async ingestionJob(@Param("jobId") jobId: string) {
    return ok(await this.adminService.getIngestionJob(jobId));
  }

  @Post("ingestion-jobs/:jobId/retry")
  @UseGuards(JwtAuthGuard)
  @Roles("admin")
  async retryIngestion(@Param("jobId") jobId: string) {
    return ok(await this.adminService.retryIngestionJob(jobId));
  }

  @Get("content-units")
  @UseGuards(JwtAuthGuard)
  @Roles("admin", "teacher")
  async contentUnits(
    @Query("subjectId") subjectId?: string,
    @Query("chapterId") chapterId?: string,
    @Query("type") type?: string,
    @Query("page") page?: string,
  ) {
    return ok(await this.adminService.listContentUnits({ subjectId, chapterId, contentType: type, page }));
  }

  @Get("content-units/:id")
  @UseGuards(JwtAuthGuard)
  @Roles("admin", "teacher")
  async contentUnit(@Param("id") id: string) {
    return ok(await this.adminService.getContentUnit(id));
  }

  @Patch("content-units/:id")
  @UseGuards(JwtAuthGuard)
  @Roles("admin")
  async updateContentUnit(@Param("id") id: string, @Body() dto: UpdateContentUnitDto) {
    return ok(await this.adminService.updateContentUnit(id, dto));
  }

  @Get("assets/:id")
  @UseGuards(JwtAuthGuard)
  @Roles("admin", "teacher")
  async asset(@Param("id") id: string) {
    return ok(await this.adminService.getAsset(id));
  }

  @Get("admin/model-providers")
  @UseGuards(JwtAuthGuard)
  @Roles("admin")
  async modelProviders() {
    return ok(await this.adminService.listModelProviders());
  }

  @Patch("admin/model-providers/:id")
  @UseGuards(JwtAuthGuard)
  @Roles("admin")
  async updateModelProvider(@Param("id") id: string, @Body() dto: UpdateModelProviderDto) {
    return ok(await this.adminService.updateModelProvider(id, dto));
  }

  @Get("admin/exam-mode")
  @UseGuards(JwtAuthGuard)
  @Roles("admin")
  async examMode() {
    return ok(await this.adminService.getExamMode());
  }

  @Patch("admin/exam-mode")
  @UseGuards(JwtAuthGuard)
  @Roles("admin")
  async updateExamMode(@Body() dto: UpdateExamModeDto) {
    return ok(await this.adminService.updateExamMode(dto));
  }

  @Post("admin/reindex")
  @UseGuards(JwtAuthGuard)
  @Roles("admin")
  async reindex(
    @CurrentUser() user: { userId: string },
    @Body() body: { textbookVersionId: string },
  ) {
    return ok(await this.adminService.reindex(body.textbookVersionId, user.userId));
  }
}
