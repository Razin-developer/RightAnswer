import { Module } from "@nestjs/common";

import { BillingModule } from "../billing/billing.module";

import { TeacherController } from "./teacher.controller";
import { TeacherService } from "./teacher.service";

@Module({
  imports: [BillingModule],
  controllers: [TeacherController],
  providers: [TeacherService],
})
export class TeacherModule {}
