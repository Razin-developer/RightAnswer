import { Module } from "@nestjs/common";

import { IngestionModule } from "../ingestion/ingestion.module";

import { AdminController } from "./admin.controller";
import { AdminService } from "./admin.service";

@Module({
  imports: [IngestionModule],
  controllers: [AdminController],
  providers: [AdminService],
  exports: [AdminService],
})
export class AdminModule {}
