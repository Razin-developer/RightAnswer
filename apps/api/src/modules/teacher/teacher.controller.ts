import { Body, Controller, Get, Post, Query, UseGuards } from "@nestjs/common";

import { CurrentUser } from "../common/current-user.decorator";
import { JwtAuthGuard } from "../common/jwt-auth.guard";
import { ok } from "../common/response.util";
import { Roles } from "../common/roles.decorator";

import { GenerateWorksheetDto, VerifyAnswerDto } from "./teacher.dto";
import { TeacherService } from "./teacher.service";

@Controller("teacher")
export class TeacherController {
  constructor(private readonly teacherService: TeacherService) {}

  @Post("verify-answer")
  @UseGuards(JwtAuthGuard)
  @Roles("teacher", "admin")
  async verifyAnswer(
    @CurrentUser() user: { userId: string },
    @Body() dto: VerifyAnswerDto,
  ) {
    return ok(await this.teacherService.verifyAnswer(user.userId, dto));
  }

  @Post("worksheets")
  @UseGuards(JwtAuthGuard)
  @Roles("teacher", "admin")
  async worksheets(
    @CurrentUser() user: { userId: string },
    @Body() dto: GenerateWorksheetDto,
  ) {
    return ok(await this.teacherService.generateWorksheet(user.userId, dto));
  }

  @Get("common-doubts")
  @UseGuards(JwtAuthGuard)
  @Roles("teacher", "admin")
  async commonDoubts(
    @Query("subjectId") subjectId?: string,
    @Query("chapterId") chapterId?: string,
  ) {
    return ok(await this.teacherService.commonDoubts(subjectId, chapterId));
  }
}
