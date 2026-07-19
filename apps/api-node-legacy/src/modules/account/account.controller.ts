import { Body, Controller, Get, Patch, Post, UseGuards } from "@nestjs/common";

import { CurrentUser } from "../common/current-user.decorator";
import { JwtAuthGuard } from "../common/jwt-auth.guard";
import { ok } from "../common/response.util";
import { Roles } from "../common/roles.decorator";

import { AccountService } from "./account.service";

@Controller()
export class AccountController {
  constructor(private readonly accountService: AccountService) {}

  @Get("users/me")
  @UseGuards(JwtAuthGuard)
  async me(@CurrentUser() user: { userId: string }) {
    return ok(await this.accountService.me(user.userId));
  }

  @Patch("users/me")
  @UseGuards(JwtAuthGuard)
  async updateMe(
    @CurrentUser() user: { userId: string },
    @Body() body: { preferredLanguage?: "en" | "ml"; schoolName?: string },
  ) {
    return ok(await this.accountService.updateProfile(user.userId, body));
  }

  @Get("users/me/history")
  @UseGuards(JwtAuthGuard)
  async history(@CurrentUser() user: { userId: string }) {
    return ok(await this.accountService.answerHistory(user.userId));
  }

  @Post("feedback")
  @UseGuards(JwtAuthGuard)
  async feedback(
    @CurrentUser() user: { userId: string },
    @Body() body: { answerCacheId: string; rating: number; issueType?: string; comment?: string },
  ) {
    return ok(await this.accountService.addFeedback(user.userId, body));
  }

  @Get("feedback")
  @UseGuards(JwtAuthGuard)
  @Roles("admin")
  async listFeedback() {
    return ok(await this.accountService.listFeedback());
  }

  @Get("subscriptions/me")
  @UseGuards(JwtAuthGuard)
  async subscription(@CurrentUser() user: { userId: string }) {
    return ok(await this.accountService.subscription(user.userId));
  }

  @Post("subscriptions/checkout")
  @UseGuards(JwtAuthGuard)
  async checkout(@Body() body: { planCode: string }) {
    return ok(this.accountService.checkout(body.planCode));
  }

  @Get("usage/me")
  @UseGuards(JwtAuthGuard)
  async usage(@CurrentUser() user: { userId: string }) {
    return ok(await this.accountService.usage(user.userId));
  }

  @Get("usage-limits")
  @UseGuards(JwtAuthGuard)
  @Roles("admin")
  async usageLimits() {
    return ok(await this.accountService.usageLimits());
  }
}
