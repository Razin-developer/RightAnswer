import { Module } from "@nestjs/common";

import { BillingModule } from "../billing/billing.module";

import { ModelGatewayService } from "./model-gateway.service";

@Module({
  imports: [BillingModule],
  providers: [ModelGatewayService],
  exports: [ModelGatewayService],
})
export class ProvidersModule {}
