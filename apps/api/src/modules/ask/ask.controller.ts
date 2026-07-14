import { Body, Controller, Post, UseGuards } from "@nestjs/common";

import { BillingService } from "../billing/billing.service";
import { CurrentUser } from "../common/current-user.decorator";
import { JwtAuthGuard } from "../common/jwt-auth.guard";
import { ok } from "../common/response.util";

import { AskQuestionDto } from "./ask.dto";
import { AskService } from "./ask.service";

@Controller()
export class AskController {
  constructor(
    private readonly askService: AskService,
    private readonly billing: BillingService,
  ) {}

  @Post("ask")
  @UseGuards(JwtAuthGuard)
  async ask(
    @CurrentUser() user: { userId: string },
    @Body() dto: AskQuestionDto,
  ) {
    return ok(await this.askService.ask(user.userId, dto), {
      planCode: await this.billing.getUserPlan(user.userId),
    });
  }
}
