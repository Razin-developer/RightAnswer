import { Module } from "@nestjs/common";

import { BillingModule } from "../billing/billing.module";

import { AccountController } from "./account.controller";
import { AccountService } from "./account.service";

@Module({
  imports: [BillingModule],
  controllers: [AccountController],
  providers: [AccountService],
})
export class AccountModule {}
