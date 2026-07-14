import { performance } from "node:perf_hooks";

import { getScriptContext } from "./textbook-script-shared";
import { detectChapterIndex, extractPdfPagesFromFile } from "../src/modules/ingestion/local-textbook-pipeline";

async function main() {
  const { embedding, options } = getScriptContext(process.argv.slice(2));
  const startedAt = performance.now();

  console.log("[debug] extracting pages");
  const pages = await extractPdfPagesFromFile(options.pdfPath, embedding);
  console.log(
    JSON.stringify(
      {
        stage: "pages_extracted",
        pageCount: pages.length,
        firstPages: pages.slice(0, Math.min(8, pages.length)).map((page) => ({
          pdfPageNumber: page.pdfPageNumber,
          charCount: page.charCount,
          tocScore: page.tocScore,
          likelyImagePage: page.likelyImagePage,
          ocrUsed: page.ocrUsed,
        })),
        elapsedMs: Math.round(performance.now() - startedAt),
      },
      null,
      2,
    ),
  );

  console.log("[debug] detecting chapters");
  const detection = await detectChapterIndex({
    pdfPath: options.pdfPath,
    pages,
    outputDir: "storage/exports/ingestion",
    chromePath: options.chromePath,
    tocScanPages: options.tocScanPages,
    forceCodexToc: options.forceCodexToc,
    indexPages: options.indexPages,
    manualChapters: options.manualChapters,
  });

  console.log(
    JSON.stringify(
      {
        stage: "chapter_detection_complete",
        elapsedMs: Math.round(performance.now() - startedAt),
        chapters: detection.chapters,
        evidence: detection.evidence,
      },
      null,
      2,
    ),
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
