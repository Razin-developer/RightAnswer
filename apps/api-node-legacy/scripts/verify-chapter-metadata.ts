/**
 * verify-chapter-metadata.ts
 *
 * READ-ONLY verification script. Does NOT modify the database or any files
 * (other than writing informational JSON previews under
 * storage/exports/ingestion/chapter-verification/, which mirrors what
 * `textbook:detect-chapters` already does for its own preview output).
 *
 * For every TextbookVersion in the database, this script:
 *   1. Reads the DB's Chapter rows (chapterNumber, title) for that version.
 *   2. Re-runs the SAME chapter-detection logic the ingestion pipeline used
 *      (local-textbook-pipeline.ts -> writeChapterDetectionPreview, which
 *      wraps detectChapterIndex / extractPdfPagesFromFile) directly against
 *      the version's source PDF under storage/imports/textbooks/... This is
 *      the pipeline's own text/TOC-based heuristic (there is no PDF
 *      outline/bookmark step anywhere in the ingestion code - it parses the
 *      textual "Contents" page(s) of each book), so re-running it is the
 *      correct way to check the pipeline's output against its own input.
 *   3. Compares DB chapters vs. freshly-detected chapters by chapterNumber,
 *      and reports any missing / extra / mismatched-title / out-of-order
 *      chapters.
 *
 * Requirements (same as the rest of the ingestion tooling):
 *   - DATABASE_URL reachable (read from the repo-root .env, same as other
 *     apps/api-node-legacy scripts).
 *   - `python` on PATH with PyMuPDF (`fitz`) installed, and optionally
 *     `rapidocr_onnxruntime` for OCR fallback pages (extractPdfPagesFromFile
 *     shells out to a generated Python script - this is the pipeline's own
 *     extraction mechanism, not something invented for this checker).
 *   - The source PDFs actually pulled locally (git-lfs), not just pointer
 *     stubs. The script explicitly checks for this and reports it clearly
 *     per textbook version instead of silently skipping.
 *
 * Run from apps/api-node-legacy (or via the pnpm filter from repo root):
 *   pnpm --filter @right-answer/api-node-legacy textbook:verify-chapters
 *   # or, from apps/api-node-legacy directly:
 *   pnpm textbook:verify-chapters
 *   # or directly with tsx:
 *   npx tsx scripts/verify-chapter-metadata.ts
 *
 * Optional flags:
 *   --limit <n>        only process the first n TextbookVersions (for a quick smoke test)
 *   --subject <code>   only process versions whose Subject.code matches (e.g. biology)
 *   --json <path>      also write the full structured report as JSON to <path>
 *
 * This script only reads from the database (via Prisma) and reads PDF files
 * from disk. It never calls prisma.chapter.create/update/delete or writes
 * anything under storage/imports or storage/textbooks.
 */

import { existsSync } from "node:fs";
import { mkdir, readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { prisma } from "@right-answer/database";

import { EmbeddingService } from "../src/modules/common/embedding.service";
import { writeChapterDetectionPreview } from "../src/modules/ingestion/local-textbook-pipeline";
import { loadLocalEnvFile } from "./textbook-script-shared";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
// apps/api-node-legacy/scripts -> repo root
const REPO_ROOT = path.resolve(__dirname, "..", "..", "..");

interface DbChapterRow {
  chapterNumber: number;
  title: string;
  startPage: number | null;
  endPage: number | null;
}

interface DetectedChapterRow {
  chapterNumber: number;
  title: string;
  pdfStartPage: number;
  pdfEndPage?: number;
  source: string;
  matchReason?: string;
}

interface MismatchDetail {
  kind: "missing_in_pdf" | "missing_in_db" | "title_mismatch" | "out_of_order" | "duplicate_chapter_number";
  chapterNumber?: number;
  dbTitle?: string;
  pdfTitle?: string;
  detail?: string;
}

interface VersionReport {
  versionId: string;
  versionLabel: string;
  subjectCode: string;
  medium: string;
  partLabel: string | null;
  pdfPath: string;
  status: "ok" | "mismatch" | "blocked";
  blockedReason?: string;
  dbChapters: DbChapterRow[];
  pdfChapters?: DetectedChapterRow[];
  mismatches: MismatchDetail[];
  frontMatterAssumptionHolds?: boolean;
  frontMatterNote?: string;
}

function parseCliArgs(argv: string[]) {
  const result: { limit?: number; subject?: string; json?: string } = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--limit") result.limit = Number(argv[++i]);
    else if (arg === "--subject") result.subject = argv[++i];
    else if (arg === "--json") result.json = argv[++i];
  }
  return result;
}

function partLabelToSlug(partLabel: string | null): string {
  if (!partLabel) return "full";
  return partLabel
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "-");
}

function normalizeTitleForCompare(title: string): string {
  return title
    .normalize("NFKC")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, " ");
}

async function isRealPdfFile(pdfPath: string): Promise<{ ok: true } | { ok: false; reason: string }> {
  if (!existsSync(pdfPath)) {
    return { ok: false, reason: `File does not exist at ${pdfPath}` };
  }
  const stats = await stat(pdfPath);
  // A git-lfs pointer stub is a tiny text file (~130 bytes), a real textbook
  // PDF is many megabytes. Also sanity-check the magic header.
  if (stats.size < 1024) {
    const head = await readFile(pdfPath, "utf8").catch(() => "");
    if (head.startsWith("version https://git-lfs.github.com/spec")) {
      return { ok: false, reason: `LFS pointer only (not pulled) - ${stats.size} bytes: ${head.split("\n")[0]}` };
    }
    return { ok: false, reason: `File too small to be a real PDF (${stats.size} bytes)` };
  }
  const headBuffer = await readFile(pdfPath, { encoding: null });
  const header = headBuffer.subarray(0, 5).toString("latin1");
  if (header !== "%PDF-") {
    // Could still be an LFS pointer if size happens to be >= 1024 for some reason.
    const asText = headBuffer.subarray(0, 200).toString("utf8");
    if (asText.startsWith("version https://git-lfs.github.com/spec")) {
      return { ok: false, reason: `LFS pointer only (not pulled): ${asText.split("\n")[0]}` };
    }
    return { ok: false, reason: `File does not start with %PDF- header (got ${JSON.stringify(header)})` };
  }
  return { ok: true };
}

function diffChapters(dbChapters: DbChapterRow[], pdfChapters: DetectedChapterRow[]): MismatchDetail[] {
  const mismatches: MismatchDetail[] = [];

  const dbByNumber = new Map<number, DbChapterRow>();
  for (const chapter of dbChapters) {
    if (dbByNumber.has(chapter.chapterNumber)) {
      mismatches.push({
        kind: "duplicate_chapter_number",
        chapterNumber: chapter.chapterNumber,
        detail: "Duplicate chapterNumber found among DB Chapter rows",
      });
    }
    dbByNumber.set(chapter.chapterNumber, chapter);
  }

  const pdfByNumber = new Map<number, DetectedChapterRow>();
  for (const chapter of pdfChapters) {
    pdfByNumber.set(chapter.chapterNumber, chapter);
  }

  const allNumbers = new Set<number>([...dbByNumber.keys(), ...pdfByNumber.keys()]);
  for (const chapterNumber of [...allNumbers].sort((a, b) => a - b)) {
    const dbChapter = dbByNumber.get(chapterNumber);
    const pdfChapter = pdfByNumber.get(chapterNumber);

    if (dbChapter && !pdfChapter) {
      mismatches.push({
        kind: "missing_in_pdf",
        chapterNumber,
        dbTitle: dbChapter.title,
        detail: "DB has this chapterNumber but the fresh PDF re-detection did not produce a matching entry",
      });
      continue;
    }

    if (!dbChapter && pdfChapter) {
      mismatches.push({
        kind: "missing_in_db",
        chapterNumber,
        pdfTitle: pdfChapter.title,
        detail: "Fresh PDF re-detection produced this chapterNumber but the DB has no matching Chapter row",
      });
      continue;
    }

    if (dbChapter && pdfChapter) {
      if (normalizeTitleForCompare(dbChapter.title) !== normalizeTitleForCompare(pdfChapter.title)) {
        mismatches.push({
          kind: "title_mismatch",
          chapterNumber,
          dbTitle: dbChapter.title,
          pdfTitle: pdfChapter.title,
        });
      }
    }
  }

  // Order check: DB chapterNumbers should be strictly increasing when read
  // in the order Prisma returned them (we ask Prisma to order by
  // chapterNumber asc, so this really checks for gaps/duplicates rather than
  // literal DB row order, which is the practically meaningful definition of
  // "out of order" here).
  const sortedDbNumbers = dbChapters.map((c) => c.chapterNumber);
  for (let i = 1; i < sortedDbNumbers.length; i += 1) {
    if (sortedDbNumbers[i] <= sortedDbNumbers[i - 1]) {
      mismatches.push({
        kind: "out_of_order",
        detail: `DB chapters not strictly increasing: chapterNumber ${sortedDbNumbers[i]} follows ${sortedDbNumbers[i - 1]}`,
      });
    }
  }

  return mismatches;
}

async function main() {
  loadLocalEnvFile();
  const cli = parseCliArgs(process.argv.slice(2));

  const versions = await prisma.textbookVersion.findMany({
    where: cli.subject
      ? { textbook: { subject: { code: cli.subject } } }
      : undefined,
    include: {
      textbook: { include: { subject: true } },
      chapters: { orderBy: { chapterNumber: "asc" } },
    },
    orderBy: [{ textbook: { subject: { code: "asc" } } }, { textbook: { medium: "asc" } }, { versionLabel: "asc" }],
  });

  const selected = cli.limit ? versions.slice(0, cli.limit) : versions;

  console.log(`[verify-chapter-metadata] ${selected.length} TextbookVersion row(s) to check (of ${versions.length} total)`);

  const embedding = new EmbeddingService();
  const previewOutDir = path.join(REPO_ROOT, "storage", "exports", "ingestion", "chapter-verification");
  await mkdir(previewOutDir, { recursive: true });

  const reports: VersionReport[] = [];
  let blockedCount = 0;
  let mismatchCount = 0;
  let okCount = 0;

  for (const version of selected) {
    const subjectCode = version.textbook.subject.code;
    const medium = version.textbook.medium;
    const partLabel = version.textbook.partLabel ?? null;
    const partSlug = partLabelToSlug(partLabel);
    const pdfPath = path.join(REPO_ROOT, "storage", "imports", "textbooks", subjectCode, medium, partSlug, "source.pdf");

    const dbChapters: DbChapterRow[] = version.chapters.map((chapter) => ({
      chapterNumber: chapter.chapterNumber,
      title: chapter.title,
      startPage: chapter.startPage,
      endPage: chapter.endPage,
    }));

    const report: VersionReport = {
      versionId: version.id,
      versionLabel: version.versionLabel,
      subjectCode,
      medium,
      partLabel,
      pdfPath,
      status: "ok",
      dbChapters,
      mismatches: [],
    };

    const pdfCheck = await isRealPdfFile(pdfPath);
    if (!pdfCheck.ok) {
      report.status = "blocked";
      report.blockedReason = pdfCheck.reason;
      blockedCount += 1;
      reports.push(report);
      console.log(`[BLOCKED] ${subjectCode}/${medium}/${partSlug} (${version.versionLabel}): ${pdfCheck.reason}`);
      continue;
    }

    process.stdout.write(`[checking] ${subjectCode}/${medium}/${partSlug} (${version.versionLabel}) ... `);
    const startedAt = Date.now();
    try {
      const outputPath = path.join(previewOutDir, `${subjectCode}-${medium}-${partSlug}.json`);
      const detection = await writeChapterDetectionPreview({ pdfPath, outputPath, embedding });
      const pdfChapters: DetectedChapterRow[] = detection.chapters.map((chapter) => ({
        chapterNumber: chapter.chapterNumber,
        title: chapter.title,
        pdfStartPage: chapter.pdfStartPage,
        pdfEndPage: chapter.pdfEndPage,
        source: chapter.source,
        matchReason: chapter.matchReason,
      }));
      report.pdfChapters = pdfChapters;

      // Check the "Front Matter == chapter 1" assumption specifically,
      // without assuming it holds.
      const dbFrontMatter = dbChapters.find((c) => normalizeTitleForCompare(c.title) === "front matter");
      const pdfFrontMatter = pdfChapters.find((c) => normalizeTitleForCompare(c.title) === "front matter");
      if (dbFrontMatter || pdfFrontMatter) {
        const dbNum = dbFrontMatter?.chapterNumber;
        const pdfNum = pdfFrontMatter?.chapterNumber;
        report.frontMatterAssumptionHolds = dbNum === 1;
        report.frontMatterNote = `Front Matter chapterNumber: DB=${dbNum ?? "absent"}, freshly-detected=${pdfNum ?? "absent"}`;
      }

      report.mismatches = diffChapters(dbChapters, pdfChapters);
      report.status = report.mismatches.length > 0 ? "mismatch" : "ok";
      if (report.status === "mismatch") mismatchCount += 1;
      else okCount += 1;
      console.log(`done in ${Date.now() - startedAt}ms - ${report.status}${report.mismatches.length ? ` (${report.mismatches.length} issue(s))` : ""}`);
    } catch (error) {
      report.status = "blocked";
      report.blockedReason = `Detection threw: ${error instanceof Error ? error.message : String(error)}`;
      blockedCount += 1;
      console.log(`FAILED: ${report.blockedReason}`);
    }

    reports.push(report);
  }

  console.log("\n============================================================");
  console.log("CHAPTER METADATA VERIFICATION REPORT");
  console.log("============================================================");
  console.log(`Checked: ${reports.length}   OK: ${okCount}   Mismatched: ${mismatchCount}   Blocked: ${blockedCount}\n`);

  const blocked = reports.filter((r) => r.status === "blocked");
  if (blocked.length > 0) {
    console.log(`--- BLOCKED (${blocked.length}) — could not run detection ---`);
    for (const r of blocked) {
      console.log(`  ${r.subjectCode}/${r.medium}/${partLabelToSlug(r.partLabel)} (${r.versionLabel}): ${r.blockedReason}`);
    }
    console.log("");
  }

  const mismatched = reports.filter((r) => r.status === "mismatch");
  if (mismatched.length > 0) {
    console.log(`--- MISMATCHED (${mismatched.length}) ---`);
    for (const r of mismatched) {
      console.log(`\n  ${r.subjectCode}/${r.medium}/${partLabelToSlug(r.partLabel)} (${r.versionLabel}) [textbookVersionId=${r.versionId}]`);
      for (const m of r.mismatches) {
        switch (m.kind) {
          case "missing_in_pdf":
            console.log(`    - chapter ${m.chapterNumber}: DB has "${m.dbTitle}" but fresh PDF detection found nothing at that number`);
            break;
          case "missing_in_db":
            console.log(`    - chapter ${m.chapterNumber}: fresh PDF detection found "${m.pdfTitle}" but DB has no row at that number`);
            break;
          case "title_mismatch":
            console.log(`    - chapter ${m.chapterNumber}: DB title "${m.dbTitle}" != freshly-detected title "${m.pdfTitle}"`);
            break;
          case "out_of_order":
            console.log(`    - ordering: ${m.detail}`);
            break;
          case "duplicate_chapter_number":
            console.log(`    - duplicate: chapterNumber ${m.chapterNumber} appears more than once in DB`);
            break;
        }
      }
    }
    console.log("");
  }

  const ok = reports.filter((r) => r.status === "ok");
  if (ok.length > 0) {
    console.log(`--- OK (${ok.length}) — DB chapters match a fresh re-detection from the source PDF ---`);
    for (const r of ok) {
      console.log(`  ${r.subjectCode}/${r.medium}/${partLabelToSlug(r.partLabel)} (${r.versionLabel}): ${r.dbChapters.length} chapters confirmed`);
    }
    console.log("");
  }

  // "Front Matter is chapter 1" assumption summary.
  const withFrontMatter = reports.filter((r) => r.frontMatterNote);
  const assumptionHolds = withFrontMatter.filter((r) => r.frontMatterAssumptionHolds === true);
  const assumptionFails = withFrontMatter.filter((r) => r.frontMatterAssumptionHolds !== true);
  console.log("--- 'Front Matter is chapter 1' assumption ---");
  console.log(
    `  Versions with a Front Matter entry: ${withFrontMatter.length}. Assumption (chapterNumber === 1) holds for ${assumptionHolds.length}, does NOT hold for ${assumptionFails.length}.`,
  );
  if (assumptionFails.length > 0) {
    const sample = assumptionFails[0];
    console.log(`  Example: ${sample.subjectCode}/${sample.medium} -> ${sample.frontMatterNote}`);
    console.log(`  (In this pipeline's own code, finalizeChapterRanges() assigns Front Matter chapterNumber 0, not 1, when the first detected chapter doesn't start on PDF page 1.)`);
  }

  if (cli.json) {
    const jsonPath = path.resolve(cli.json);
    await mkdir(path.dirname(jsonPath), { recursive: true });
    const { writeFile } = await import("node:fs/promises");
    await writeFile(jsonPath, JSON.stringify(reports, null, 2), "utf8");
    console.log(`\nFull structured report written to ${jsonPath}`);
  }

  await prisma.$disconnect();

  if (mismatchCount > 0 || blockedCount > 0) {
    process.exitCode = 1;
  }
}

main().catch(async (error) => {
  console.error(error);
  await prisma.$disconnect();
  process.exitCode = 1;
});
