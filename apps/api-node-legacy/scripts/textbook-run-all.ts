import { getScriptContext } from "./textbook-script-shared";
import {
  extractPdfPagesFromFile,
  runLocalTextbookPipeline,
  writeChapterDetectionPreview,
} from "../src/modules/ingestion/local-textbook-pipeline";

async function main() {
  const { prisma, embedding, options } = getScriptContext(process.argv.slice(2));

  const pages = await extractPdfPagesFromFile(options.pdfPath, embedding);
  console.log(`[1/3] extracted ${pages.length} pages from ${options.pdfPath}`);

  const detection = await writeChapterDetectionPreview({
    pdfPath: options.pdfPath,
    outputPath: `storage/exports/ingestion/${options.subjectCode}-${options.medium}-${options.versionLabel}-chapter-index.json`,
    embedding,
    chromePath: options.chromePath,
    tocScanPages: options.tocScanPages,
    forceCodexToc: options.forceCodexToc,
    interactiveConfirm: options.interactiveConfirm,
    indexPages: options.indexPages,
    manualChapters: options.manualChapters,
  });
  console.log(`[2/3] detected ${detection.chapters.length} chapters`);

  const result = await runLocalTextbookPipeline({
    prisma,
    embedding,
    options: {
      ...options,
      interactiveConfirm: false,
      indexPages:
        detection.evidence.lockedIndexPages && detection.evidence.lockedIndexPages.length > 0
          ? detection.evidence.lockedIndexPages
          : detection.evidence.tocCandidatePages.map((page) => page.pdfPageNumber),
      manualChapters: detection.chapters.map((chapter) => ({
        chapterNumber: chapter.chapterNumber,
        title: chapter.title,
        printedStartPage: chapter.printedStartPage,
      })),
      sourceType: options.sourceType ?? "manual_local_script",
      sourceDomain:
        options.sourceDomain ??
        (options.sourceUrl ? new URL(options.sourceUrl).hostname : undefined),
    },
  });
  console.log(`[3/3] ingested textbook version ${result.textbookVersionId}`);
  console.log(JSON.stringify({ ok: true, result }, null, 2));

  await prisma.$disconnect();
}

main().catch(async (error) => {
  console.error(error);
  process.exitCode = 1;
});
