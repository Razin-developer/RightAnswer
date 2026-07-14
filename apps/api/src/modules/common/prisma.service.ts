import { Injectable, OnModuleDestroy } from "@nestjs/common";

import { prisma } from "@right-answer/database";

@Injectable()
export class PrismaService implements OnModuleDestroy {
  get client() {
    return prisma;
  }

  async onModuleDestroy() {
    await prisma.$disconnect();
  }
}
