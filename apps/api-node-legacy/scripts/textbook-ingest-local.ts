import { getScriptContext } from "./textbook-script-shared";
import { runLocalTextbookPipeline } from "../src/modules/ingestion/local-textbook-pipeline";

async function main() {
  const { prisma, embedding, options } = getScriptContext(process.argv.slice(2));
  const result = await runLocalTextbookPipeline({
    prisma,
    embedding,
    options: {
      ...options,
      sourceType: options.sourceType ?? "manual_local_script",
      sourceDomain:
        options.sourceDomain ??
        (options.sourceUrl ? new URL(options.sourceUrl).hostname : undefined),
    },
  });

  console.log(JSON.stringify({ ok: true, result }, null, 2));
  await prisma.$disconnect();
}

main().catch(async (error) => {
  console.error(error);
  process.exitCode = 1;
});
