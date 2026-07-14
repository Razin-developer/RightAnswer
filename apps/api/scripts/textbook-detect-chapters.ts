import path from "node:path";

import { getScriptContext } from "./textbook-script-shared";
import { writeChapterDetectionPreview } from "../src/modules/ingestion/local-textbook-pipeline";

async function main() {
  const { embedding, options } = getScriptContext(process.argv.slice(2));
  const outputPath = path.resolve(
    process.cwd(),
    "storage",
    "exports",
    "ingestion",
    `${options.subjectCode}-${options.medium}-${options.versionLabel}-chapter-index.json`,
  );

  const detection = await writeChapterDetectionPreview({
    pdfPath: options.pdfPath,
    outputPath,
    embedding,
    chromePath: options.chromePath,
    tocScanPages: options.tocScanPages,
    forceCodexToc: options.forceCodexToc,
    interactiveConfirm: options.interactiveConfirm,
    indexPages: options.indexPages,
    manualChapters: options.manualChapters,
  });

  console.log(JSON.stringify({ ok: true, outputPath, chapters: detection.chapters }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
