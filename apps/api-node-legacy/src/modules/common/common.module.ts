import { Global, Module } from "@nestjs/common";
import { JwtModule } from "@nestjs/jwt";

import { CacheService } from "./cache.service";
import { EmbeddingService } from "./embedding.service";
import { JwtAuthGuard } from "./jwt-auth.guard";
import { MetricsService } from "./metrics.service";
import { PrismaService } from "./prisma.service";
import { RolesGuard } from "./roles.guard";
import { StorageService } from "./storage.service";

@Global()
@Module({
  imports: [
    JwtModule.register({
      secret: process.env.JWT_SECRET ?? "right-answer-dev-secret",
      signOptions: { expiresIn: "7d" },
    }),
  ],
  providers: [
    PrismaService,
    CacheService,
    EmbeddingService,
    StorageService,
    MetricsService,
    JwtAuthGuard,
    RolesGuard,
  ],
  exports: [
    PrismaService,
    CacheService,
    EmbeddingService,
    StorageService,
    MetricsService,
    JwtModule,
    JwtAuthGuard,
    RolesGuard,
  ],
})
export class CommonModule {}
