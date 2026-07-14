import { Module } from "@nestjs/common";

import { AccountModule } from "./account/account.module";
import { AdminModule } from "./admin/admin.module";
import { AskModule } from "./ask/ask.module";
import { AuthModule } from "./auth/auth.module";
import { BillingModule } from "./billing/billing.module";
import { CommonModule } from "./common/common.module";
import { RolesGuard } from "./common/roles.guard";
import { ContentModule } from "./content/content.module";
import { EvaluationModule } from "./evaluation/evaluation.module";
import { IngestionModule } from "./ingestion/ingestion.module";
import { ProvidersModule } from "./providers/providers.module";
import { TeacherModule } from "./teacher/teacher.module";

@Module({
  imports: [
    CommonModule,
    BillingModule,
    AccountModule,
    AuthModule,
    ContentModule,
    ProvidersModule,
    EvaluationModule,
    IngestionModule,
    AskModule,
    AdminModule,
    TeacherModule,
  ],
  providers: [RolesGuard],
})
export class AppModule {}
