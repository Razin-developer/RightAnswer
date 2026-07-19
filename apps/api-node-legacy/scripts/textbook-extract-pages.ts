import { writeFile } from "node:fs/promises";
import path from "node:path";

import { getScriptContext } from "./textbook-script-shared";
import { extractPdfPagesFromFile } from "../src/modules/ingestion/local-textbook-pipeline";

async function main() {
  const { embedding, options } = getScriptContext(process.argv.slice(2));
  const pages = await extractPdfPagesFromFile(options.pdfPath, embedding);

  const outputPath = path.resolve(
    process.cwd(),
    "storage",
    "exports",
    "ingestion",
    `${options.subjectCode}-${options.medium}-${options.versionLabel}-pages.json`,
  );

  await writeFile(outputPath, JSON.stringify(pages, null, 2));
  console.log(JSON.stringify({ ok: true, outputPath, pageCount: pages.length }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
