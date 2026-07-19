import { existsSync } from "node:fs";
import { appendFile, mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { execFile } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { createInterface } from "node:readline/promises";
import { promisify } from "node:util";

import type { Medium } from "@prisma/client";
import { prisma } from "@right-answer/database";
import { buildTextbookStorageKey } from "@right-answer/storage";

import { EmbeddingService } from "../src/modules/common/embedding.service";
import { runLocalTextbookPipeline } from "../src/modules/ingestion/local-textbook-pipeline";
import { getTextbookIngestionOverride } from "./textbook-ingestion-overrides";
import { loadLocalEnvFile } from "./textbook-script-shared";

interface BatchRow {
  rowNumber: number;
  subject: string;
  partLabel?: string;
  medium: Medium;
  sourceUrl: string;
  subjectCode: string;
  subjectName: string;
  title: string;
  versionLabel: string;
}

interface BatchSummaryTotals {
  requested: number;
  succeeded: number;
  failed: number;
  skipped: number;
}

interface BatchProgressState {
  completed: number;
  succeeded: number;
  failed: number;
  skipped: number;
}

const QUICK_GO_16_ROWS = [21, 22, 23, 24, 25, 26, 33, 34, 36, 41, 45, 46, 47, 48, 49, 50] as const;
const OPTIONAL_LANGUAGE_SUBJECT_CODES = new Set([
  "arabic-academic",
  "arabic-oriental",
  "hindi",
  "sanskrit-academic",
  "sanskrit-oriental",
  "urdu",
]);
const execFileAsync = promisify(execFile);

function parseArgs(argv: string[]) {
  const values: Record<string, string | boolean> = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith("--")) continue;
    const key = arg.slice(2);
    const next = argv[index + 1];
    if (!next || next.startsWith("--")) {
      values[key] = true;
      continue;
    }
    values[key] = next;
    index += 1;
  }
  return values;
}

function parseNumberListArg(value: string | boolean | undefined) {
  if (typeof value !== "string") {
    return [];
  }

  return value
    .split(",")
    .map((part) => Number(part.trim()))
    .filter((part) => Number.isFinite(part) && part > 0);
}

function formatLogMessage(args: unknown[]) {
  return args
    .map((value) => {
      if (typeof value === "string") return value;
      if (value instanceof Error) return value.stack ?? value.message;
      try {
        return JSON.stringify(value);
      } catch {
        return String(value);
      }
    })
    .join(" ");
}

async function ensureLogFile(logPath: string) {
  await mkdir(path.dirname(logPath), { recursive: true });
  await writeFile(logPath, "");
}

async function appendLog(logPath: string, level: "info" | "warn" | "error", args: unknown[]) {
  const line = `[${new Date().toISOString()}] [${level}] ${formatLogMessage(args)}\n`;
  await appendFile(logPath, line);
}

async function withConsoleTee<T>(logPaths: string[], fn: () => Promise<T>) {
  const originalLog = console.log;
  const originalWarn = console.warn;
  const originalError = console.error;

  console.log = (...args: unknown[]) => {
    for (const logPath of logPaths) {
      void appendLog(logPath, "info", args);
    }
    originalLog(...args);
  };

  console.warn = (...args: unknown[]) => {
    for (const logPath of logPaths) {
      void appendLog(logPath, "warn", args);
    }
    originalWarn(...args);
  };

  console.error = (...args: unknown[]) => {
    for (const logPath of logPaths) {
      void appendLog(logPath, "error", args);
    }
    originalError(...args);
  };

  try {
    return await fn();
  } finally {
    console.log = originalLog;
    console.warn = originalWarn;
    console.error = originalError;
  }
}

async function mapWithConcurrency<TItem, TResult>(
  items: TItem[],
  concurrency: number,
  worker: (item: TItem, index: number) => Promise<TResult>,
) {
  if (items.length === 0) {
    return [] as TResult[];
  }

  const safeConcurrency = Math.max(1, Math.min(concurrency, items.length));
  const results = new Array<TResult>(items.length);
  let nextIndex = 0;

  await Promise.all(
    Array.from({ length: safeConcurrency }, async () => {
      while (true) {
        const currentIndex = nextIndex;
        nextIndex += 1;
        if (currentIndex >= items.length) {
          break;
        }
        results[currentIndex] = await worker(items[currentIndex]!, currentIndex);
      }
    }),
  );

  return results;
}

function getWorkerCount(requested: number | undefined, itemCount: number) {
  const available = Math.max(1, (os.cpus()?.length ?? 4) - 2);
  const desired = requested && requested > 0 ? requested : available;
  return Math.max(1, Math.min(itemCount, desired, available));
}

function getPerBookWorkerBudget(rowParallel: number) {
  const available = Math.max(1, (os.cpus()?.length ?? 4) - 2);
  return Math.max(1, Math.min(8, Math.floor(available / Math.max(1, rowParallel))));
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function slugify(input: string) {
  return input
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
}

function repairText(input: string) {
  return input
    .replace(/ï¿½/g, "'")
    .replace(/â€™|â€˜/g, "'")
    .replace(/â€œ|â€/g, '"')
    .replace(/â€”|â€“/g, "-")
    .replace(/Â/g, " ");
}

function normalizePartLabel(input: string) {
  const cleaned = repairText(input).trim();
  if (!cleaned || cleaned === "-" || cleaned === "—") {
    return undefined;
  }
  return cleaned;
}

function mapMedium(input: string): Medium {
  const normalized = repairText(input).trim().toLowerCase();
  return normalized.startsWith("mal") ? "ml" : "en";
}

function mapSubject(input: string) {
  const normalized = slugify(repairText(input));
  const mappings: Record<string, { code: string; name: string }> = {
    biology: { code: "biology", name: "Biology" },
    chemistry: { code: "chemistry", name: "Chemistry" },
    physics: { code: "physics", name: "Physics" },
    mathematics: { code: "mathematics", name: "Mathematics" },
    english: { code: "english", name: "English" },
    hindi: { code: "hindi", name: "Hindi" },
    ict: { code: "ict", name: "ICT" },
    urdu: { code: "urdu", name: "Urdu" },
    "physical-education": { code: "physical-education", name: "Physical Education" },
    "social-science-i": { code: "social-science-i", name: "Social Science I" },
    "social-science-ii": { code: "social-science-ii", name: "Social Science II" },
    "malayalam-at": { code: "malayalam-at", name: "Malayalam (AT)" },
    "malayalam-bt": { code: "malayalam-bt", name: "Malayalam (BT)" },
    "arabic-academic": { code: "arabic-academic", name: "Arabic Academic" },
    "arabic-oriental": { code: "arabic-oriental", name: "Arabic Oriental" },
    "sanskrit-academic": { code: "sanskrit-academic", name: "Sanskrit Academic" },
    "sanskrit-oriental": { code: "sanskrit-oriental", name: "Sanskrit Oriental" },
  };

  return mappings[normalized] ?? {
    code: normalized,
    name: repairText(input).trim(),
  };
}

function extractGoogleDriveFileId(url: string) {
  const byPath = url.match(/\/d\/([^/]+)/i)?.[1];
  if (byPath) return byPath;

  try {
    const parsed = new URL(url);
    return parsed.searchParams.get("id") ?? undefined;
  } catch {
    return undefined;
  }
}

function parseCsvRows(csvText: string, versionPrefix: string) {
  const lines = csvText
    .split(/\r?\n/)
    .map((line) => repairText(line).trim())
    .filter(Boolean);

  return lines.slice(1).map((line, index) => {
    const [subject, part, medium, link] = line.split(",").map((value) => value.trim());
    const partLabel = normalizePartLabel(part);
    const mappedSubject = mapSubject(subject);
    const mappedMedium = mapMedium(medium);
    const title = `Class 10 ${mappedSubject.name}${partLabel ? ` ${partLabel}` : ""}`;
    const versionLabel = [versionPrefix, mappedSubject.code, mappedMedium, partLabel ? slugify(partLabel) : "full"]
      .filter(Boolean)
      .join("-");

    return {
      rowNumber: index + 2,
      subject,
      partLabel,
      medium: mappedMedium,
      sourceUrl: link,
      subjectCode: mappedSubject.code,
      subjectName: mappedSubject.name,
      title,
      versionLabel,
    } satisfies BatchRow;
  });
}

function parseContentDispositionFileName(header: string | null) {
  if (!header) return undefined;
  const match = header.match(/filename=\"?([^\";]+)\"?/i);
  return match?.[1];
}

async function downloadGoogleDrivePdfViaPython(params: {
  fileId: string;
  sourceUrl: string;
  outputPath: string;
}) {
  const scriptPath = path.join(os.tmpdir(), `right-answer-gdrive-${Date.now()}-${Math.random().toString(16).slice(2)}.py`);

  await writeFile(
    scriptPath,
    [
      "import json, os, re, sys, requests",
      "file_id = sys.argv[1]",
      "source_url = sys.argv[2]",
      "output_path = sys.argv[3]",
      "session = requests.Session()",
      "session.headers.update({'User-Agent': 'Mozilla/5.0'})",
      "view_urls = []",
      "if source_url:",
      "    view_urls.append(source_url)",
      "if file_id:",
      "    view_urls.extend([",
      "        f'https://drive.google.com/file/d/{file_id}/view?usp=drive_link',",
      "        f'https://drive.google.com/file/d/{file_id}/view',",
      "        f'https://drive.google.com/open?id={file_id}',",
      "    ])",
      "seen = set()",
      "download_url = None",
      "for view_url in view_urls:",
      "    if not view_url or view_url in seen:",
      "        continue",
      "    seen.add(view_url)",
      "    response = session.get(view_url, timeout=(10, 30))",
      "    response.raise_for_status()",
      "    html = response.text",
      "    item_match = re.search(r'itemJson:\\s*(\\[.*?\\])\\s*};', html)",
      "    if item_match:",
      "        try:",
      "            item = json.loads(item_match.group(1))",
      "            if len(item) > 18 and isinstance(item[18], str) and item[18]:",
      "                download_url = item[18]",
      "                break",
      "        except Exception:",
      "            pass",
      "    direct_match = re.search(r'https://drive\\\\.usercontent\\\\.google\\\\.com/uc\\?id\\\\u003d[^\"\\\\]+', html)",
      "    if direct_match:",
      "        download_url = direct_match.group(0).replace('\\\\u003d', '=').replace('\\\\u0026', '&').replace('\\\\/', '/')",
      "        break",
      "if not download_url:",
      "    raise RuntimeError('google_drive_download_url_not_found')",
      "download_response = session.get(download_url, allow_redirects=True, timeout=(10, 60), stream=True)",
      "download_response.raise_for_status()",
      "first_chunk = next(download_response.iter_content(64), b'')",
      "if not first_chunk.startswith(b'%PDF'):",
      "    raise RuntimeError('google_drive_download_not_pdf')",
      "os.makedirs(os.path.dirname(output_path), exist_ok=True)",
      "with open(output_path, 'wb') as handle:",
      "    handle.write(first_chunk)",
      "    for chunk in download_response.iter_content(1024 * 256):",
      "        if chunk:",
      "            handle.write(chunk)",
      "print(output_path)",
    ].join("\n"),
    "utf8",
  );

  try {
    const { stdout } = await execFileAsync(
      "python",
      [scriptPath, params.fileId, params.sourceUrl, params.outputPath],
      {
        windowsHide: true,
        timeout: 120_000,
        maxBuffer: 2 * 1024 * 1024,
      },
    );

    return stdout.trim() || params.outputPath;
  } finally {
    await rm(scriptPath, { force: true }).catch(() => undefined);
  }
}

async function downloadPdf(row: BatchRow, downloadRoot: string) {
  const outputDir = path.join(downloadRoot, row.subjectCode, row.medium, row.partLabel ? slugify(row.partLabel) : "full");
  await mkdir(outputDir, { recursive: true });

  const findExistingPdfFallback = async () => {
    if (!existsSync(outputDir)) {
      return null;
    }

    const entries = await readdir(outputDir, { withFileTypes: true });
    const pdfCandidates = entries
      .filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith(".pdf"))
      .map((entry) => path.join(outputDir, entry.name))
      .sort((left, right) => left.localeCompare(right));

    return pdfCandidates[0] ?? null;
  };

  const existingPdfPath = await findExistingPdfFallback();
  if (existingPdfPath) {
    return existingPdfPath;
  }

  const fileId = extractGoogleDriveFileId(row.sourceUrl);
  const outputPath = path.join(outputDir, "source.pdf");

  if (fileId) {
    try {
      const drivenPath = await downloadGoogleDrivePdfViaPython({
        fileId,
        sourceUrl: row.sourceUrl,
        outputPath,
      });
      if (drivenPath && existsSync(drivenPath)) {
        return drivenPath;
      }
    } catch {
      // Fall through to the direct fetch path below.
    }
  }

  const directUrl = fileId ? `https://drive.google.com/uc?export=download&id=${fileId}` : row.sourceUrl;
  const response = await fetch(directUrl, { redirect: "follow" }).catch(() => null);
  if (!response) {
    const fallbackPath = await findExistingPdfFallback();
    if (fallbackPath) {
      return fallbackPath;
    }
    throw new Error("fetch failed");
  }
  if (!response.ok) {
    const fallbackPath = await findExistingPdfFallback();
    if (fallbackPath) {
      return fallbackPath;
    }
    throw new Error(`Download failed with HTTP ${response.status}`);
  }

  const contentType = response.headers.get("content-type") ?? "";
  if (!/pdf|octet-stream|application\/binary/i.test(contentType)) {
    const fallbackPath = await findExistingPdfFallback();
    if (fallbackPath) {
      return fallbackPath;
    }
    throw new Error(`Unexpected content-type for PDF download: ${contentType}`);
  }

  const fileName =
    parseContentDispositionFileName(response.headers.get("content-disposition")) ??
    `${row.title.replace(/[^\p{L}\p{N}]+/gu, " ").trim()}.pdf`;

  if (existsSync(outputPath)) {
    return outputPath;
  }

  const buffer = Buffer.from(await response.arrayBuffer());
  if (buffer.subarray(0, 4).toString() !== "%PDF") {
    const fallbackPath = await findExistingPdfFallback();
    if (fallbackPath) {
      return fallbackPath;
    }
    throw new Error("Downloaded file is not a PDF.");
  }

  const finalOutputPath = path.join(outputDir, fileName || "source.pdf");
  await writeFile(finalOutputPath, buffer);
  return finalOutputPath;
}

function getRowImportDir(row: BatchRow, downloadRoot: string) {
  return path.join(downloadRoot, row.subjectCode, row.medium, row.partLabel ? slugify(row.partLabel) : "full");
}

function getRowStorageDirs(row: BatchRow) {
  const rawFilePath = buildTextbookStorageKey({
    syllabus: "sslc",
    subjectSlug: row.subjectCode,
    medium: row.medium,
    versionLabel: row.versionLabel,
    kind: "raw",
    fileName: "placeholder.txt",
  });
  const processedFilePath = buildTextbookStorageKey({
    syllabus: "sslc",
    subjectSlug: row.subjectCode,
    medium: row.medium,
    versionLabel: row.versionLabel,
    kind: "processed",
    fileName: "placeholder.txt",
  });

  return {
    rawDir: path.resolve(process.cwd(), "storage", path.dirname(rawFilePath)),
    processedDir: path.resolve(process.cwd(), "storage", path.dirname(processedFilePath)),
  };
}

async function clearRowStorage(row: BatchRow, downloadRoot: string) {
  const { rawDir, processedDir } = getRowStorageDirs(row);
  await Promise.all([
    rm(rawDir, { recursive: true, force: true }),
    rm(processedDir, { recursive: true, force: true }),
  ]);
}

async function purgeRowDatabase(row: BatchRow) {
  const subject = await prisma.subject.findFirst({
    where: {
      code: row.subjectCode,
      classLevel: 10,
      syllabus: "Kerala SSLC",
    },
    select: { id: true },
  });

  if (!subject) {
    return {
      textbookCount: 0,
      versionCount: 0,
      chapterCount: 0,
    };
  }

  const textbooks = await prisma.textbook.findMany({
    where: {
      subjectId: subject.id,
      medium: row.medium,
      classLevel: 10,
      syllabus: "Kerala SSLC",
      partLabel: row.partLabel ?? null,
    },
    select: { id: true },
  });
  const textbookIds = textbooks.map((textbook) => textbook.id);
  if (textbookIds.length === 0) {
    return {
      textbookCount: 0,
      versionCount: 0,
      chapterCount: 0,
    };
  }

  const versions = await prisma.textbookVersion.findMany({
    where: {
      textbookId: { in: textbookIds },
    },
    select: { id: true },
  });
  const versionIds = versions.map((version) => version.id);

  const chapters =
    versionIds.length > 0
      ? await prisma.chapter.findMany({
          where: { textbookVersionId: { in: versionIds } },
          select: { id: true },
        })
      : [];
  const chapterIds = chapters.map((chapter) => chapter.id);

  if (chapterIds.length > 0) {
    await prisma.retrievalLog.deleteMany({
      where: {
        chapterId: { in: chapterIds },
      },
    });
    await prisma.answerCache.deleteMany({
      where: {
        chapterId: { in: chapterIds },
      },
    });
  }
  if (versionIds.length > 0) {
    await prisma.exactCache.deleteMany({
      where: {
        textbookVersionId: { in: versionIds },
      },
    });
    await prisma.ingestionJob.deleteMany({
      where: {
        textbookVersionId: { in: versionIds },
      },
    });
  }
  await prisma.ingestionJob.deleteMany({
    where: {
      textbookId: { in: textbookIds },
    },
  });
  await prisma.textbook.deleteMany({
    where: {
      id: { in: textbookIds },
    },
  });

  return {
    textbookCount: textbookIds.length,
    versionCount: versionIds.length,
    chapterCount: chapterIds.length,
  };
}

async function purgeDerivedCaches() {
  await prisma.retrievalLog.deleteMany({});
  await prisma.exactCache.deleteMany({});
  await prisma.semanticCache.deleteMany({});
  await prisma.answerCache.deleteMany({});

  await Promise.all([
    rm(path.resolve(process.cwd(), "storage/cache"), { recursive: true, force: true }),
    rm(path.resolve(process.cwd(), "storage/exports/ingestion"), { recursive: true, force: true }),
  ]);
}

function isRetryableRowError(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  const normalized = message.toLowerCase();

  return (
    normalized.includes("can't reach database server") ||
    normalized.includes("connection terminated unexpectedly") ||
    normalized.includes("server closed the connection unexpectedly") ||
    normalized.includes("timed out fetching") ||
    normalized.includes("fetch failed") ||
    normalized.includes("download failed with http 429") ||
    normalized.includes("download failed with http 500") ||
    normalized.includes("download failed with http 502") ||
    normalized.includes("download failed with http 503") ||
    normalized.includes("download failed with http 504") ||
    normalized.includes("unexpected content-type for pdf download")
  );
}

function buildTotals(results: Array<Record<string, unknown>>): BatchSummaryTotals {
  return {
    requested: results.length,
    succeeded: results.filter((item) => item.ok === true).length,
    failed: results.filter((item) => item.ok === false).length,
    skipped: results.filter((item) => item.skipped === true).length,
  };
}

async function confirmBatch(rows: BatchRow[]) {
  const rl = createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  try {
    console.log(`About to process ${rows.length} textbooks.`);
    console.log(
      rows
        .slice(0, 10)
        .map((row) => `  row ${row.rowNumber}: ${row.title} [${row.medium}]`)
        .join("\n"),
    );
    if (rows.length > 10) {
      console.log(`  ... and ${rows.length - 10} more`);
    }
    const answer = (await rl.question("Continue? [Y/n]: ")).trim().toLowerCase();
    return !answer || answer === "y" || answer === "yes";
  } finally {
    rl.close();
  }
}

async function processRow(params: {
  row: BatchRow;
  batchLogPath: string;
  logRoot: string;
  downloadRoot: string;
  embedding: EmbeddingService;
  reingest: boolean;
  fresh: boolean;
  allowRowLogTee: boolean;
  forceCodexToc: boolean;
  maxAttempts: number;
}) {
  const { row, batchLogPath, logRoot, downloadRoot, embedding, reingest, fresh, allowRowLogTee, forceCodexToc, maxAttempts } = params;
  const rowLogPath = path.join(logRoot, `${row.versionLabel}.log`);
  await ensureLogFile(rowLogPath);

  const execute = async (): Promise<Record<string, unknown>> => {
    console.log(`[start] row ${row.rowNumber} -> ${row.title}`);
    const override = getTextbookIngestionOverride(row);
    if (override?.notes?.length) {
      console.log(`[override] row ${row.rowNumber} -> ${override.notes.join(" | ")}`);
    }

    const manifestPath = path.resolve(
      process.cwd(),
      "storage",
      buildTextbookStorageKey({
        syllabus: "sslc",
        subjectSlug: row.subjectCode,
        medium: row.medium,
        versionLabel: row.versionLabel,
        kind: "processed",
        fileName: "manifest.json",
      }),
    );

    if (fresh) {
      const purgeSummary = await purgeRowDatabase(row);
      await clearRowStorage(row, downloadRoot);
      console.log(
        `[fresh] cleared ${row.versionLabel} (textbooks=${purgeSummary.textbookCount}, versions=${purgeSummary.versionCount}, chapters=${purgeSummary.chapterCount})`,
      );
    }

    const existingTextbook = await prisma.textbook.findFirst({
      where: {
        subject: {
          code: row.subjectCode,
          classLevel: 10,
          syllabus: "Kerala SSLC",
        },
        medium: row.medium,
        classLevel: 10,
        syllabus: "Kerala SSLC",
        partLabel: row.partLabel ?? null,
        versions: {
          some: {
            status: "published",
          },
        },
      },
      include: {
        versions: {
          where: { status: "published" },
          take: 1,
          orderBy: { updatedAt: "desc" },
        },
      },
    });

    if (!fresh && !reingest && (existsSync(manifestPath) || existingTextbook)) {
      console.warn(`[skip] existing processed textbook for ${row.title}`);
      return {
        rowNumber: row.rowNumber,
        title: row.title,
        medium: row.medium,
        versionLabel: row.versionLabel,
        skipped: true,
        reason: existingTextbook ? "textbook_already_published" : "manifest_exists",
        existingVersionId: existingTextbook?.versions[0]?.id ?? null,
      };
    }

    for (let attempt = 1; attempt <= Math.max(1, maxAttempts); attempt += 1) {
      try {
        if (attempt > 1) {
          const purgeSummary = await purgeRowDatabase(row);
          await clearRowStorage(row, downloadRoot);
          await prisma.$disconnect().catch(() => undefined);
          await prisma.$connect().catch(() => undefined);
          console.warn(
            `[retry] re-cleared ${row.versionLabel} before attempt ${attempt} (textbooks=${purgeSummary.textbookCount}, versions=${purgeSummary.versionCount}, chapters=${purgeSummary.chapterCount})`,
          );
        }

        console.log(`[download] fetching source pdf for ${row.title} (attempt ${attempt}/${Math.max(1, maxAttempts)})`);
        const pdfPath = await downloadPdf(row, downloadRoot);
        console.log(`[download] stored source pdf at ${pdfPath}`);

        const result = await runLocalTextbookPipeline({
          prisma,
          embedding,
          options: {
            pdfPath,
            subjectCode: row.subjectCode,
            subjectName: row.subjectName,
            medium: row.medium,
            versionLabel: row.versionLabel,
            partLabel: row.partLabel,
            title: row.title,
            sourceUrl: row.sourceUrl,
            sourceType: "user_supplied_csv",
            sourceDomain: new URL(row.sourceUrl).hostname,
            classLevel: 10,
            syllabus: "Kerala SSLC",
            publisher: "Kerala SCERT / User-supplied source list",
            interactiveConfirm: false,
            tocScanPages: override?.tocScanPages,
            forceCodexToc: forceCodexToc || override?.forceCodexToc === true,
            indexPages: override?.indexPages,
            manualChapters: override?.manualChapters,
          },
        });

        console.log(`[ok] row ${row.rowNumber} -> ${row.title}`);
        return {
          rowNumber: row.rowNumber,
          title: row.title,
          medium: row.medium,
          versionLabel: row.versionLabel,
          pdfPath,
          ok: true,
          overrideApplied: Boolean(override),
          attemptsUsed: attempt,
          ...result,
        };
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        const retryable = attempt < Math.max(1, maxAttempts) && isRetryableRowError(error);
        console.error(
          `[failed] row ${row.rowNumber} -> ${row.title} (attempt ${attempt}/${Math.max(1, maxAttempts)}): ${message}`,
        );
        if (!retryable) {
          return {
            rowNumber: row.rowNumber,
            title: row.title,
            medium: row.medium,
            versionLabel: row.versionLabel,
            ok: false,
            attemptsUsed: attempt,
            error: message,
          };
        }

        const delayMs = Math.min(30_000, 5_000 * attempt);
        console.warn(`[retry] row ${row.rowNumber} waiting ${delayMs}ms before retry`);
        await sleep(delayMs);
      }
    }

    return {
      rowNumber: row.rowNumber,
      title: row.title,
      medium: row.medium,
      versionLabel: row.versionLabel,
      ok: false,
      attemptsUsed: Math.max(1, maxAttempts),
      error: "Row failed after retry budget was exhausted.",
    };
  };

  if (allowRowLogTee) {
    return withConsoleTee([batchLogPath, rowLogPath], execute);
  }

  await appendLog(batchLogPath, "info", [`[start-worker] ${row.versionLabel}`]);
  await appendLog(rowLogPath, "info", [`[start-worker] ${row.versionLabel}`]);
  const result = await execute();
  await appendLog(batchLogPath, result.ok === false ? "error" : "info", [result]);
  await appendLog(rowLogPath, result.ok === false ? "error" : "info", [result]);
  return result;
}

async function logProgress(params: {
  batchLogPath: string;
  total: number;
  row: BatchRow;
  result: Record<string, unknown>;
  progress: BatchProgressState;
}) {
  const { batchLogPath, total, row, result, progress } = params;
  progress.completed += 1;
  if (result.ok === true) {
    progress.succeeded += 1;
  } else if (result.ok === false) {
    progress.failed += 1;
  } else if (result.skipped === true) {
    progress.skipped += 1;
  }

  const line =
    `[progress] completed ${progress.completed}/${total}` +
    ` | succeeded ${progress.succeeded}` +
    ` | failed ${progress.failed}` +
    ` | skipped ${progress.skipped}` +
    ` | last row ${row.rowNumber} ${row.title} [${row.medium}]`;
  console.log(line);
  await appendLog(batchLogPath, "info", [line]);
}

async function main() {
  loadLocalEnvFile();
  const args = parseArgs(process.argv.slice(2));
  const csvPath = String(args["csv"] ?? "");
  if (!csvPath) {
    throw new Error("Missing required --csv <path> argument.");
  }

  const versionPrefix = String(args["version-prefix"] ?? "2025-batch");
  const limit = args["limit"] ? Number(args["limit"]) : undefined;
  const offset = args["offset"] ? Number(args["offset"]) : 0;
  const subjectFilter = args["subject"] ? slugify(String(args["subject"])) : undefined;
  const mediumFilter = args["medium"] ? mapMedium(String(args["medium"])) : undefined;
  const reingest = Boolean(args["reingest"]);
  const fresh = Boolean(args["fresh"] || args["clean"]);
  const interactiveConfirm = Boolean(args["interactive"] || args["confirm"]);
  const runTag = String(args["run-tag"] ?? Date.now());
  const requestedParallel = args["parallel"] ? Number(args["parallel"]) : undefined;
  const maxAttempts = args["attempts"] ? Number(args["attempts"]) : 3;
  const requestedChapterWorkers = args["chapter-workers"] ? Number(args["chapter-workers"]) : undefined;
  const requestedOcrWorkers = args["ocr-workers"] ? Number(args["ocr-workers"]) : undefined;
  const selectedRows = parseNumberListArg(args["rows"]);
  const quickGo16 = Boolean(args["quick-go-16"]);
  const coreMalayalamEnglishOnly = Boolean(args["core-ml-en-only"] || args["supported-only"]);
  const requestedCodexTocWorkers = args["codex-toc-workers"] ? Number(args["codex-toc-workers"]) : undefined;
  const forceCodexToc = Boolean(args["force-codex-toc"]);
  const enableCodexToc = Boolean(args["enable-codex-toc"] || forceCodexToc);
  const downloadRoot = path.resolve(
    process.cwd(),
    String(args["download-dir"] ?? "storage/imports/textbooks"),
  );
  const logRoot = path.resolve(process.cwd(), "storage/logs/ingestion");
  const batchLogPath = path.join(logRoot, `batch-${versionPrefix}-${runTag}.log`);

  const csvText = await readFile(csvPath, "utf8");
  let rows = parseCsvRows(csvText, versionPrefix);

  if (subjectFilter) {
    rows = rows.filter((row) => row.subjectCode === subjectFilter);
  }
  if (mediumFilter) {
    rows = rows.filter((row) => row.medium === mediumFilter);
  }
  if (quickGo16) {
    rows = rows.filter((row) => QUICK_GO_16_ROWS.includes(row.rowNumber as (typeof QUICK_GO_16_ROWS)[number]));
  }
  if (coreMalayalamEnglishOnly) {
    rows = rows.filter((row) => !OPTIONAL_LANGUAGE_SUBJECT_CODES.has(row.subjectCode));
  }
  if (selectedRows.length > 0) {
    const rowSet = new Set(selectedRows);
    rows = rows.filter((row) => rowSet.has(row.rowNumber));
  }
  if (offset > 0) {
    rows = rows.slice(offset);
  }
  if (limit && limit > 0) {
    rows = rows.slice(0, limit);
  }

  if (interactiveConfirm) {
    const accepted = await confirmBatch(rows);
    if (!accepted) {
      throw new Error("Batch processing cancelled by user.");
    }
  }

  await ensureLogFile(batchLogPath);
  await appendLog(batchLogPath, "info", [
    "starting batch",
    {
      csvPath,
      versionPrefix,
      runTag,
      fresh,
      reingest,
      rowCount: rows.length,
      requestedParallel: requestedParallel ?? null,
      maxAttempts,
      requestedChapterWorkers: requestedChapterWorkers ?? null,
      requestedOcrWorkers: requestedOcrWorkers ?? null,
      selectedRows: selectedRows.length > 0 ? selectedRows : null,
      quickGo16,
      coreMalayalamEnglishOnly,
      enableCodexToc,
      subjectFilter: subjectFilter ?? null,
      mediumFilter: mediumFilter ?? null,
    },
  ]);

  const embedding = new EmbeddingService();
  const parallel = getWorkerCount(requestedParallel, rows.length);
  const perBookWorkerBudget = getPerBookWorkerBudget(parallel);
  const chapterWorkerBudget =
    requestedChapterWorkers && requestedChapterWorkers > 0
      ? Math.max(1, Math.min(8, requestedChapterWorkers))
      : perBookWorkerBudget;
  const ocrWorkerBudget =
    requestedOcrWorkers && requestedOcrWorkers > 0
      ? Math.max(1, Math.min(8, requestedOcrWorkers))
      : chapterWorkerBudget;
  const allowRowLogTee = parallel === 1;
  console.log(`[batch] using ${parallel} row workers`);
  console.log(`[batch] per-book worker budget ${perBookWorkerBudget}`);
  console.log(`[batch] chapter workers ${chapterWorkerBudget}`);
  console.log(`[batch] ocr workers ${ocrWorkerBudget}`);
  await appendLog(batchLogPath, "info", [`using ${parallel} row workers`]);
  await appendLog(batchLogPath, "info", [`per-book worker budget ${perBookWorkerBudget}`]);
  await appendLog(batchLogPath, "info", [`chapter workers ${chapterWorkerBudget}`]);
  await appendLog(batchLogPath, "info", [`ocr workers ${ocrWorkerBudget}`]);
  process.env.RIGHT_ANSWER_TEXTBOOK_CHAPTER_WORKERS = String(chapterWorkerBudget);
  process.env.RIGHT_ANSWER_TEXTBOOK_OCR_WORKERS = String(ocrWorkerBudget);
  process.env.RIGHT_ANSWER_CODEX_TOC_WORKERS = String(Math.max(1, Math.min(2, requestedCodexTocWorkers ?? 2)));
  process.env.RIGHT_ANSWER_ENABLE_CODEX_TOC = enableCodexToc ? "1" : process.env.RIGHT_ANSWER_ENABLE_CODEX_TOC ?? "0";

  if (fresh) {
    console.log("[fresh] clearing derived caches and previous storage for selected rows");
    await purgeDerivedCaches();
  }

  const seenSourceKeys = new Set<string>();
  const seededResults: Array<Record<string, unknown>> = [];
  const uniqueRows: BatchRow[] = [];
  for (const row of rows) {
    const sourceKey = [
      extractGoogleDriveFileId(row.sourceUrl) ?? row.sourceUrl,
      row.subjectCode,
      row.medium,
      row.partLabel ?? "full",
    ].join("::");
    if (seenSourceKeys.has(sourceKey)) {
      seededResults.push({
        rowNumber: row.rowNumber,
        title: row.title,
        medium: row.medium,
        versionLabel: row.versionLabel,
        skipped: true,
        reason: "duplicate_source_in_csv",
      });
      continue;
    }
    seenSourceKeys.add(sourceKey);
    uniqueRows.push(row);
  }

  const progress: BatchProgressState = {
    completed: 0,
    succeeded: 0,
    failed: 0,
    skipped: seededResults.length,
  };
  if (seededResults.length > 0) {
    await appendLog(batchLogPath, "info", [
      `[progress] completed 0/${rows.length} | succeeded 0 | failed 0 | skipped ${seededResults.length} | seeded duplicate rows`,
    ]);
  }

  const processedResults = await mapWithConcurrency(uniqueRows, parallel, async (row) => {
    const result = await processRow({
      row,
      batchLogPath,
      logRoot,
      downloadRoot,
      embedding,
      reingest,
      fresh,
      allowRowLogTee,
      forceCodexToc,
      maxAttempts,
    });
    await logProgress({
      batchLogPath,
      total: rows.length,
      row,
      result,
      progress,
    });
    return result;
  });

  const results = [...seededResults, ...processedResults];

  const totals = buildTotals(results);
  const summaryPath = path.resolve(
    process.cwd(),
    "storage/exports/ingestion",
    `batch-${versionPrefix}-${runTag}.json`,
  );
  await mkdir(path.dirname(summaryPath), { recursive: true });
  await writeFile(
    summaryPath,
    JSON.stringify(
      {
        csvPath,
        versionPrefix,
        runTag,
        processedAt: new Date().toISOString(),
        fresh,
        totals,
        results,
      },
      null,
      2,
    ),
  );

  await appendLog(batchLogPath, "info", [{ ok: true, summaryPath, totals }]);
  console.log(JSON.stringify({ ok: true, summaryPath, batchLogPath, totals }, null, 2));

  await prisma.$disconnect();
}

main().catch(async (error) => {
  console.error(error);
  process.exitCode = 1;
  await prisma.$disconnect();
});
