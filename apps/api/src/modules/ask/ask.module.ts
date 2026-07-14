import { Module } from "@nestjs/common";

import { BillingModule } from "../billing/billing.module";
import { ContentModule } from "../content/content.module";
import { ProvidersModule } from "../providers/providers.module";

import { AskController } from "./ask.controller";
import { AskService } from "./ask.service";

@Module({
  imports: [BillingModule, ProvidersModule, ContentModule],
  controllers: [AskController],
  providers: [AskService],
})
export class AskModule {}
