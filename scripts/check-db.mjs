import path from "node:path";
import { pathToFileURL } from "node:url";

async function loadPrismaClient() {
  const clientEntry = path.resolve(
    process.cwd(),
    "packages/database/node_modules/@prisma/client/index.js",
  );
  const module = await import(pathToFileURL(clientEntry).href);
  return module.PrismaClient;
}

const PrismaClient = await loadPrismaClient();
const prisma = new PrismaClient();

try {
  const [textbooks, chapters, contentUnits, embeddings] = await Promise.all([
    prisma.textbook.count(),
    prisma.chapter.count(),
    prisma.contentUnit.count(),
    prisma.embedding.count(),
  ]);

  console.log(
    JSON.stringify(
      {
        ok: true,
        databaseUrl: process.env.DATABASE_URL ?? null,
        counts: {
          textbooks,
          chapters,
          contentUnits,
          embeddings,
        },
        embedding: {
          backend: process.env.RIGHT_ANSWER_EMBEDDING_BACKEND ?? "hf-transformers",
          model: process.env.RIGHT_ANSWER_EMBEDDING_MODEL ?? "Qwen/Qwen3-Embedding-4B",
          dimensions: Number(process.env.RIGHT_ANSWER_EMBEDDING_DIMENSIONS ?? "2560"),
        },
      },
      null,
      2,
    ),
  );
} catch (error) {
  console.error(
    JSON.stringify(
      {
        ok: false,
        error: error instanceof Error ? error.message : String(error),
      },
      null,
      2,
    ),
  );
  process.exitCode = 1;
} finally {
  await prisma.$disconnect();
}
