import { createHash, randomUUID } from "node:crypto";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";
import { createInterface } from "node:readline/promises";
import { promisify } from "node:util";

import type {
  AssetType,
  ContentLanguage,
  ContentType,
  IngestionStage,
  JobStatus,
  Medium,
  Prisma,
  PrismaClient,
} from "@prisma/client";
import { APPROVED_TEXTBOOK_SOURCE_DOMAINS, DEFAULT_EMBEDDING_MODEL, STORAGE_ROOT } from "@right-answer/config";
import { buildTextbookStorageKey, LocalStorageAdapter, type StorageAdapter } from "@right-answer/storage";
import pdf from "pdf-parse";

const execFileAsync = promisify(execFile);
let vectorColumnSupported: boolean | null = null;

export interface TextbookPipelineEmbeddingAdapter {
  normalizeText(input: string): string;
  embedText(text: string, mode?: "document" | "query"): Promise<number[]>;
  embedTexts(texts: string[], mode?: "document" | "query"): Promise<number[][]>;
  toVectorLiteral(values: number[]): string;
}

export interface TextbookPipelineOptions {
  pdfPath: string;
  subjectCode: string;
  subjectName?: string;
  medium: Medium;
  versionLabel: string;
  partLabel?: string;
  academicYear?: string;
  title?: string;
  sourceUrl?: string;
  sourceType?: string;
  sourceDomain?: string;
  classLevel?: number;
  syllabus?: string;
  publisher?: string;
  language?: ContentLanguage;
  tocScanPages?: number;
  forceCodexToc?: boolean;
  chromePath?: string;
  keepDebugArtifacts?: boolean;
  existingVersionId?: string;
  interactiveConfirm?: boolean;
  indexPages?: number[];
  manualChapters?: ManualChapterInput[];
}

export interface ManualChapterInput {
  chapterNumber: number;
  title: string;
  printedStartPage: number;
}

export interface ExtractedPdfPage {
  pdfPageNumber: number;
  rawText: string;
  normalizedText: string;
  charCount: number;
  lineCount: number;
  ocrUsed: boolean;
  likelyImagePage: boolean;
  tocScore: number;
  textBlocks: ExtractedTextBlock[];
  embeddedImageCount: number;
}

export interface ExtractedTextBlock {
  text: string;
  bbox: [number, number, number, number];
  blockType: number;
}

export interface ChapterIndexEntry {
  chapterNumber: number;
  title: string;
  printedStartPage: number;
  pdfStartPage: number;
  pdfEndPage?: number;
  confidence: number;
  source: "text" | "codex" | "manual";
  matchReason?: string;
}

export interface DetectedAsset {
  localId: string;
  assetType: AssetType;
  pageNumber: number;
  captionText: string;
  rawText?: string;
  filePath: string;
  nearbyContentLocalIds: string[];
  metadata: Record<string, unknown>;
}

export interface StructuredContentUnit {
  localId: string;
  pageNumber: number;
  chapterNumber: number;
  contentType: ContentType;
  text: string;
  normalizedText: string;
  parentLocalId?: string;
  keywords: string[];
  metadata: Record<string, unknown>;
}

export interface StructuredQuestionRecord {
  localId: string;
  exerciseLocalId: string;
  parentLocalId?: string;
  chapterNumber: number;
  pageNumber: number;
  contentUnitLocalId?: string;
  title: string;
  questionText: string;
  questionNumber?: string;
  answerHint?: string;
}

export interface StructuredExerciseRecord {
  localId: string;
  chapterNumber: number;
  pageStart: number;
  pageEnd: number;
  title: string;
  exerciseType: string;
}

export interface ProcessedTextbookArtifacts {
  pages: ExtractedPdfPage[];
  chapters: ChapterIndexEntry[];
  contentUnits: StructuredContentUnit[];
  assets: DetectedAsset[];
  exercises: StructuredExerciseRecord[];
  questions: StructuredQuestionRecord[];
  tocEvidence: Record<string, unknown>;
  pageArtifacts: Array<Record<string, unknown>>;
}

export interface TextbookPipelineResult {
  jobId: string;
  textbookVersionId: string;
  pageCount: number;
  chapterCount: number;
  contentUnitCount: number;
  assetCount: number;
  exerciseCount: number;
  questionCount: number;
  storagePrefix: string;
  chapters: ChapterIndexEntry[];
}

function parseArgs(argv: string[]) {
  const result: Record<string, string | boolean | string[]> = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith("--")) continue;
    const key = arg.slice(2);
    const next = argv[index + 1];
    if (!next || next.startsWith("--")) {
      const current = result[key];
      if (Array.isArray(current)) {
        current.push("true");
      } else if (typeof current === "string") {
        result[key] = [current, "true"];
      } else {
        result[key] = true;
      }
      continue;
    }
    const current = result[key];
    if (Array.isArray(current)) {
      current.push(next);
    } else if (typeof current === "string") {
      result[key] = [current, next];
    } else {
      result[key] = next;
    }
    index += 1;
  }
  return result;
}

function firstArgValue(value: string | boolean | string[] | undefined) {
  if (Array.isArray(value)) {
    return value[0];
  }
  return typeof value === "string" ? value : undefined;
}

function repeatedArgValues(value: string | boolean | string[] | undefined) {
  if (Array.isArray(value)) {
    return value.filter((entry) => entry !== "true");
  }
  if (typeof value === "string") {
    return value === "true" ? [] : [value];
  }
  return [];
}

function parseNumberList(values: string[]) {
  return Array.from(
    new Set(
      values
        .flatMap((value) => value.split(/[,\s]+/))
        .map((value) => Number(value.trim()))
        .filter((value) => Number.isInteger(value) && value > 0),
    ),
  ).sort((left, right) => left - right);
}

function parseManualChapterStrings(values: string[]): ManualChapterInput[] {
  const entries = values
    .flatMap((value) => value.split(";"))
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const [chapterNumberRaw, titleRaw, printedStartPageRaw] = entry.split("|").map((part) => part.trim());
      const chapterNumber = Number(chapterNumberRaw);
      const printedStartPage = Number(printedStartPageRaw);

      if (!chapterNumber || !titleRaw || !printedStartPage) {
        throw new Error(
          `Invalid --chapter value "${entry}". Use the format chapterNumber|title|printedStartPage.`,
        );
      }

      return {
        chapterNumber,
        title: titleRaw,
        printedStartPage,
      };
    });

  return sanitizeChapterEntries(
    entries.map((entry) => ({
      ...entry,
      pdfStartPage: entry.printedStartPage,
      confidence: 1,
      source: "manual" as const,
      matchReason: "cli_manual",
    })),
  ).map((entry) => ({
    chapterNumber: entry.chapterNumber,
    title: entry.title,
    printedStartPage: entry.printedStartPage,
  }));
}

export function parsePipelineCliArgs(argv: string[]) {
  const args = parseArgs(argv);
  const pdfPath = String(firstArgValue(args["pdf"]) ?? "");
  const subjectCode = String(firstArgValue(args["subject"]) ?? "");
  const medium = (String(firstArgValue(args["medium"]) ?? "en") as Medium) || "en";
  const versionLabel = String(firstArgValue(args["version"]) ?? "");

  if (!pdfPath || !subjectCode || !versionLabel) {
    throw new Error(
      "Missing required arguments. Use --pdf <path> --subject <code> --version <label> [--medium en|ml].",
    );
  }

  return {
    pdfPath,
    subjectCode,
    subjectName: firstArgValue(args["subject-name"]) ? String(firstArgValue(args["subject-name"])) : undefined,
    medium,
    versionLabel,
    partLabel: firstArgValue(args["part"]) ? String(firstArgValue(args["part"])) : undefined,
    academicYear: firstArgValue(args["academic-year"]) ? String(firstArgValue(args["academic-year"])) : undefined,
    title: firstArgValue(args["title"]) ? String(firstArgValue(args["title"])) : undefined,
    sourceUrl: firstArgValue(args["source-url"]) ? String(firstArgValue(args["source-url"])) : undefined,
    sourceType: firstArgValue(args["source-type"]) ? String(firstArgValue(args["source-type"])) : undefined,
    sourceDomain: firstArgValue(args["source-domain"]) ? String(firstArgValue(args["source-domain"])) : undefined,
    chromePath: firstArgValue(args["chrome-path"]) ? String(firstArgValue(args["chrome-path"])) : undefined,
    tocScanPages: firstArgValue(args["toc-scan-pages"]) ? Number(firstArgValue(args["toc-scan-pages"])) : undefined,
    forceCodexToc: Boolean(args["force-codex-toc"]),
    keepDebugArtifacts: Boolean(args["keep-debug-artifacts"]),
    interactiveConfirm: Boolean(args["interactive"] || args["confirm"]),
    indexPages: parseNumberList(repeatedArgValues(args["index-page"]).concat(repeatedArgValues(args["index-pages"]))),
    manualChapters: parseManualChapterStrings(repeatedArgValues(args["chapter"])),
  } satisfies Partial<TextbookPipelineOptions>;
}

function slugify(input: string) {
  return input
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
}

function chunkArray<T>(items: T[], chunkSize: number) {
  const chunks: T[][] = [];
  for (let index = 0; index < items.length; index += chunkSize) {
    chunks.push(items.slice(index, index + chunkSize));
  }
  return chunks;
}

function normalizeWhitespace(input: string) {
  return input.replace(/\u00a0/g, " ").replace(/\r/g, "").replace(/\t/g, " ").replace(/[ ]{2,}/g, " ");
}

const LOCALIZED_DIGIT_GROUPS = [
  ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"],
  ["۰", "۱", "۲", "۳", "۴", "۵", "۶", "۷", "۸", "۹"],
  ["०", "१", "२", "३", "४", "५", "६", "७", "८", "९"],
  ["൦", "൧", "൨", "൩", "൪", "൫", "൬", "൭", "൮", "൯"],
] as const;

const LOCALIZED_DIGIT_MAP: Map<string, string> = new Map(
  LOCALIZED_DIGIT_GROUPS.flatMap((group) => group.map((digit, index) => [digit, String(index)] as const)),
);

function normalizeLocalizedDigits(input: string) {
  return [...input].map((char) => LOCALIZED_DIGIT_MAP.get(char) ?? char).join("");
}

function repairExtractedText(input: string) {
  return normalizeLocalizedDigits(
    input
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, " ")
    .replace(/ï¿½/g, "'")
    .replace(/â€™|â€˜/g, "'")
    .replace(/â€œ|â€/g, '"')
    .replace(/â€”|â€“/g, "-")
    .replace(/Â(?=\s|[A-Za-z])/g, " ")
    .replace(/\uFFFD/g, "'")
    .replace(/�/g, "'")
    .replace(/([A-Za-z])�([A-Za-z])/g, "$1'$2")
      .replace(/([A-Za-z])\s+'\s+([A-Za-z])/g, "$1'$2")
      .replace(/([A-Za-z])'\s+([A-Za-z])/g, "$1'$2"),
  );
}

function normalizeForSearch(input: string) {
  return normalizeWhitespace(repairExtractedText(input))
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function keywordSlice(normalizedText: string) {
  return Array.from(new Set(normalizedText.split(" ").filter(Boolean).slice(0, 12)));
}

function titleCaseFromCode(input: string) {
  return input
    .split(/[-_\s]+/)
    .filter(Boolean)
    .map((token) => token.slice(0, 1).toUpperCase() + token.slice(1))
    .join(" ");
}

function splitPdfTextByPage(text: string, pageCount: number) {
  const blocks = text
    .split(/\f+/)
    .map((block) => block.trim())
    .filter((block) => block.length > 0);

  if (blocks.length === pageCount) {
    return blocks;
  }

  if (blocks.length > pageCount) {
    return blocks.slice(0, pageCount);
  }

  return Array.from({ length: pageCount }, (_, index) => blocks[index] ?? "");
}

function computeTocScore(text: string) {
  const lines = normalizeWhitespace(text)
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);

  if (!lines.length) {
    return 0;
  }

  const tocTerms = ["contents", "content", "chapter", "unit", "വിഷയസൂചിക", "അധ്യായം"];
  const termHits = lines.filter((line) => tocTerms.some((term) => line.toLowerCase().includes(term))).length;
  const trailingNumbers = lines.filter((line) => /\b\d{1,3}\s*$/.test(line)).length;
  const dottedLeaders = lines.filter((line) => /[.·•…]{2,}/.test(line)).length;

  const contentsHintBoost = containsContentsHint(text) ? 6 : 0;

  return termHits * 4 + trailingNumbers * 2 + dottedLeaders * 2 + contentsHintBoost + Math.min(lines.length, 10) * 0.1;
}

function containsContentsHint(text: string) {
  return (
    /\b(contents?|chapter|unit|index)\b/i.test(text) ||
    /വിഷയസൂചിക|അധ്യായം|ഉള്ളടക്കം|अनुक्रमणिका|विषयसूची|अध्याय|इकाई|इकााई|इकााइ|पाठ|فہرست|باب|درس|المحتويات|الوحدة/.test(
      text,
    )
  );
}

function isIgnoredTocTitle(title: string) {
  return /^(contents?|activities|let.?s assess|extended activities|further reading|let.?s find|icons|project|ict possibilities|std\.?\s*x|standard\s*[-–]?\s*x|(?:mathematics|physics|chemistry|biology|english|malayalam|social science|ict|physical education)(?:\s+standard)?\s*[-–]?\s*x)$/i.test(
    title.trim(),
  );
}

function sanitizeTocTitle(title: string) {
  title = title.replace(/[-–—_]{3,}/g, " ");
  return repairExtractedText(normalizeWhitespace(title)).replace(/[.·•…]{2,}/g, " ").replace(/\s+/g, " ").trim();
}

function countUnicodeLetters(value: string) {
  return (value.match(/[\p{L}\p{M}]/gu) ?? []).length;
}

const WEAK_ENGLISH_TITLE_TOKENS = new Set([
  "a",
  "an",
  "and",
  "as",
  "at",
  "for",
  "from",
  "in",
  "into",
  "more",
  "of",
  "on",
  "or",
  "so",
  "than",
  "the",
  "to",
  "with",
]);

function countLatinLetters(value: string) {
  return (value.match(/[A-Za-z]/g) ?? []).length;
}

function isMostlyLatinTitle(value: string) {
  const latinLetters = countLatinLetters(value);
  const unicodeLetters = countUnicodeLetters(value);
  return latinLetters >= 3 && latinLetters / Math.max(1, unicodeLetters) >= 0.7;
}

function hasEnglishTitleCaseSignal(value: string) {
  return value
    .split(/\s+/)
    .filter(Boolean)
    .some((token) => /^[A-Z][A-Za-z]/.test(token));
}

function isWeakEnglishTitle(value: string) {
  if (!isMostlyLatinTitle(value)) {
    return false;
  }

  const trimmed = value.trim();
  const tokens = trimmed
    .split(/\s+/)
    .map((token) => token.replace(/[^A-Za-z]/g, "").toLowerCase())
    .filter(Boolean);

  if (tokens.length === 0) {
    return true;
  }

  if (/[,:;]$/.test(trimmed)) {
    return true;
  }

  if (tokens.length === 1) {
    return tokens[0]!.length <= 4 || WEAK_ENGLISH_TITLE_TOKENS.has(tokens[0]!);
  }

  const meaningfulTokenCount = tokens.filter((token) => !WEAK_ENGLISH_TITLE_TOKENS.has(token)).length;
  if (meaningfulTokenCount === 0) {
    return true;
  }

  return !hasEnglishTitleCaseSignal(trimmed) && tokens.length <= 5;
}

function hasEncodedTextArtifacts(value: string) {
  return /[ÃÂâËΩ˛™∫¶±Æ∆ıÚ¢£‰¿]/u.test(value);
}

function looksLikeTocTitle(title: string) {
  const cleaned = sanitizeTocTitle(title);
  if (!cleaned || isIgnoredTocTitle(cleaned)) return false;
  if (cleaned.length < 3 || cleaned.length > 120) return false;

  const letters = countUnicodeLetters(cleaned);
  const digits = (cleaned.match(/\d/g) ?? []).length;
  const mathSymbols = (cleaned.match(/[=÷×+\/*^]/g) ?? []).length;
  const punctuation = (cleaned.match(/[,:;()[\]{}]/g) ?? []).length;
  const encodedArtifactText = hasEncodedTextArtifacts(cleaned);

  if (letters < 3) return false;
  if (isWeakEnglishTitle(cleaned)) return false;
  if (digits > Math.max(3, Math.floor(letters * 0.35))) return false;
  if (mathSymbols > (encodedArtifactText ? 2 : 0)) return false;
  if (punctuation > (encodedArtifactText ? Math.max(6, Math.floor(cleaned.length * 0.18)) : Math.max(3, Math.floor(cleaned.length * 0.08)))) return false;
  if (!/[\p{L}\p{M}]{3,}/u.test(cleaned) && !encodedArtifactText) return false;

  return true;
}

function looksLikeTocEntryText(text: string) {
  const cleaned = repairExtractedText(normalizeWhitespace(text)).replace(/\n+/g, " ").trim();
  if (!cleaned) return false;

  if (
    /^(?:chapter|unit)?\s*\d{1,2}[.\s:-]+.+?\s+\d{1,3}(?:\s*[-–]\s*\d{1,3})?$/i.test(cleaned) ||
    /^\d{1,2}\.?\s+.+?\s+\d{1,3}(?:\s*[-–]\s*\d{1,3})?$/i.test(cleaned)
  ) {
    return true;
  }

  if (/[.·•…]{4,}/.test(cleaned) && /\b\d{1,3}\s*$/.test(cleaned)) {
    return true;
  }

  const titlePageMatch = cleaned.match(/^(.+?)\s+(\d{1,3}(?:\s*[-–]\s*\d{1,3})?)$/u);
  if (titlePageMatch) {
    const title = sanitizeTocTitle(titlePageMatch[1]);
    const printedStartPage = parsePrintedStartPage(titlePageMatch[2]);
    if (printedStartPage && looksLikeTocTitle(title)) {
      return true;
    }
  }

  return false;
}

function parsePrintedStartPage(value: string | undefined) {
  if (!value) return null;
  const match = sanitizeTocTitle(value).match(/(\d{1,3})(?:\s*[-–]\s*\d{1,3})?$/);
  return match ? Number(match[1]) : null;
}

function isStandalonePageReference(line: string) {
  return /^\d{1,3}(?:\s*[-â€“]\s*\d{1,3})?$/.test(sanitizeTocTitle(line));
}

function parseChapterNumberTitleLine(line: string) {
  const cleaned = sanitizeTocTitle(line);
  const match = cleaned.match(/^(?:chapter|unit)?\s*(\d{1,2})[.\s:-]+(.+)$/iu);
  if (!match) {
    return null;
  }

  const chapterNumber = Number(match[1]);
  const title = sanitizeTocTitle(match[2]);
  if (!chapterNumber || !looksLikeTocTitle(title)) {
    return null;
  }

  return { chapterNumber, title };
}

function extractSequentialTitlePageEntries(lines: string[]) {
  const entries: Array<{
    chapterNumber?: number | null;
    title: string;
    printedStartPage: number;
    confidence: number;
    matchReason: string;
  }> = [];
  let pendingChapterNumber: number | null = null;
  let titleBuffer: string[] = [];

  const flushBuffer = (pageLine: string) => {
    const printedStartPage = parsePrintedStartPage(pageLine);
    const title = sanitizeTocTitle(titleBuffer.join(" "));
    if (!printedStartPage || !looksLikeTocTitle(title)) {
      titleBuffer = [];
      return;
    }

    entries.push({
      chapterNumber: pendingChapterNumber,
      title,
      printedStartPage,
      confidence: pendingChapterNumber ? 0.91 : 0.84,
      matchReason: pendingChapterNumber ? "block_multi_line_numbered" : "block_multi_line_title_page",
    });
    pendingChapterNumber = null;
    titleBuffer = [];
  };

  for (const rawLine of lines) {
    const line = sanitizeTocTitle(rawLine);
    if (!line || containsContentsHint(line)) {
      continue;
    }

    const explicitMatch =
      line.match(/^(?:chapter|unit)?\s*(\d{1,2})[.\s:-]+(.+?)\s+(\d{1,3}(?:\s*[-â€“]\s*\d{1,3})?)$/iu) ??
      line.match(/^(\d{1,2})\s+(.+?)\s+(\d{1,3}(?:\s*[-â€“]\s*\d{1,3})?)$/u);
    if (explicitMatch) {
      const title = sanitizeTocTitle(explicitMatch[2]);
      const printedStartPage = parsePrintedStartPage(explicitMatch[3]);
      if (printedStartPage && looksLikeTocTitle(title)) {
        entries.push({
          chapterNumber: Number(explicitMatch[1]),
          title,
          printedStartPage,
          confidence: 0.9,
          matchReason: "line_explicit_title_page",
        });
        pendingChapterNumber = null;
        titleBuffer = [];
        continue;
      }
    }

    if (/^\d{1,2}$/.test(line)) {
      pendingChapterNumber = Number(line);
      titleBuffer = [];
      continue;
    }

    if (isStandalonePageReference(line)) {
      if (titleBuffer.length > 0) {
        flushBuffer(line);
      }
      continue;
    }

    const numberTitle = parseChapterNumberTitleLine(line);
    if (numberTitle) {
      pendingChapterNumber = numberTitle.chapterNumber;
      titleBuffer = [numberTitle.title];
      continue;
    }

    titleBuffer.push(line);
  }

  return entries;
}

function extractHierarchicalChapterEntries(lines: string[]) {
  const numberedTitleLines = lines
    .map((line, lineIndex) => {
      const parsed = parseChapterNumberTitleLine(line);
      if (!parsed) {
        return null;
      }

      return {
        ...parsed,
        lineIndex,
      };
    })
    .filter((value): value is { chapterNumber: number; title: string; lineIndex: number } => Boolean(value));

  if (numberedTitleLines.length < 2) {
    return [];
  }

  const headingCandidates: Array<{ chapterNumber: number; title: string; lineIndex: number }> = [];
  for (let chapterNumber = 1; chapterNumber <= 20; chapterNumber += 1) {
    const candidates = numberedTitleLines
      .filter((candidate) => candidate.chapterNumber === chapterNumber)
      .sort((left, right) => left.title.length - right.title.length || left.lineIndex - right.lineIndex);
    if (candidates.length === 0) {
      if (headingCandidates.length >= 2) {
        break;
      }
      continue;
    }

    headingCandidates.push(candidates[0]!);
  }

  if (headingCandidates.length < 2) {
    return [];
  }

  return headingCandidates.flatMap((heading, index) => {
    const nextHeadingIndex = headingCandidates[index + 1]?.lineIndex ?? lines.length;
    const firstPageLine = lines.slice(heading.lineIndex + 1, nextHeadingIndex).find((line) => isStandalonePageReference(line));
    const printedStartPage = parsePrintedStartPage(firstPageLine);
    if (!printedStartPage) {
      return [];
    }

    return [
      {
        chapterNumber: heading.chapterNumber,
        title: heading.title,
        printedStartPage,
        confidence: 0.88,
        matchReason: "hierarchical_heading_first_child_page",
      },
    ];
  });
}

function extractNumberThenTitleFirstChildEntries(lines: string[]) {
  const entries: Array<{ chapterNumber: number; title: string; printedStartPage: number; confidence: number; matchReason: string }> =
    [];

  const normalizePageForTitle = (title: string, pageLine: string, printedStartPage: number) => {
    if (/[\u0600-\u06FF]/u.test(title) && /^0\d$/.test(sanitizeTocTitle(pageLine))) {
      return Number(sanitizeTocTitle(pageLine).split("").reverse().join(""));
    }

    return printedStartPage;
  };

  for (let index = 0; index < lines.length - 1; index += 1) {
    const chapterNumberLine = sanitizeTocTitle(lines[index] ?? "");
    const titleLine = sanitizeTocTitle(lines[index + 1] ?? "");
    const previousLine = sanitizeTocTitle(lines[index - 1] ?? "");
    if (!/^\d{1,2}$/.test(chapterNumberLine) || !looksLikeTocTitle(titleLine)) {
      continue;
    }
    if (index > 0 && !containsContentsHint(previousLine) && !isStandalonePageReference(previousLine)) {
      continue;
    }

    const nextHeadingIndex = lines.findIndex(
      (line, lineIndex) =>
        lineIndex > index + 1 &&
        /^\d{1,2}$/.test(sanitizeTocTitle(line)) &&
        looksLikeTocTitle(sanitizeTocTitle(lines[lineIndex + 1] ?? "")),
    );
    const segmentEnd = nextHeadingIndex === -1 ? lines.length : nextHeadingIndex;
    const pageLine = lines.slice(index + 2, segmentEnd).find((line) => isStandalonePageReference(line));
    const printedStartPage = parsePrintedStartPage(pageLine);
    if (!printedStartPage) {
      continue;
    }

    entries.push({
      chapterNumber: Number(chapterNumberLine),
      title: titleLine,
      printedStartPage: normalizePageForTitle(titleLine, pageLine!, printedStartPage),
      confidence: 0.89,
      matchReason: "number_then_title_first_child_page",
    });
  }

  return entries;
}

function extractTocTitlePagePairs(lines: string[]) {
  const inlinePairs = lines
    .map((line) => {
      const dottedMatch = line.match(/^(.+?)[.·•…]{2,}\s*(\d{1,3}(?:\s*[-–]\s*\d{1,3})?)$/u);
      const simpleMatch = dottedMatch ?? line.match(/^(.+?)\s+(\d{1,3}(?:\s*[-–]\s*\d{1,3})?)$/u);
      if (!simpleMatch) {
        return null;
      }

      const title = sanitizeTocTitle(simpleMatch[1]);
      const printedStartPage = parsePrintedStartPage(simpleMatch[2]);
      if (!printedStartPage || !looksLikeTocTitle(title)) {
        return null;
      }

      return {
        title,
        printedStartPage,
      };
    })
    .filter((value): value is { title: string; printedStartPage: number } => Boolean(value));

  if (inlinePairs.length > 0) {
    return inlinePairs;
  }

  const trailingPage = lines.at(-1);
  if (!trailingPage || !/^\d{1,3}(?:\s*[-–]\s*\d{1,3})?$/.test(trailingPage)) {
    return [];
  }

  const title = sanitizeTocTitle(lines.slice(0, -1).join(" "));
  const printedStartPage = parsePrintedStartPage(trailingPage);
  if (!printedStartPage || !looksLikeTocTitle(title)) {
    return [];
  }

  return [
    {
      title,
      printedStartPage,
    },
  ];
}

function extractRangeStartEntries(lines: string[]) {
  const entries: Array<{ chapterNumber?: number | null; title: string; printedStartPage: number; confidence: number; matchReason: string }> =
    [];

  for (let index = 0; index < lines.length; index += 1) {
    const currentLine = sanitizeTocTitle(lines[index] ?? "");
    const nextLine = sanitizeTocTitle(lines[index + 1] ?? "");
    const nextPage = parsePrintedStartPage(nextLine);
    const currentPage = parsePrintedStartPage(currentLine);
    const numberTitle = parseChapterNumberTitleLine(currentLine);

    if (numberTitle && nextPage) {
      entries.push({
        chapterNumber: numberTitle.chapterNumber,
        title: numberTitle.title,
        printedStartPage: nextPage,
        confidence: 0.86,
        matchReason: "line_range_start_pair",
      });
      continue;
    }

    const inlineRangeMatch =
      currentLine.match(/^(?:chapter|unit)?\s*(\d{1,2})[.\s:-]+(.+?)\s+(\d{1,3})\s*[-â€“]\s*\d{1,3}$/iu) ??
      currentLine.match(/^(\d{1,2})[.\s:-]+(.+?)\s+(\d{1,3})\s*[-â€“]\s*\d{1,3}$/u);
    if (inlineRangeMatch) {
      const title = sanitizeTocTitle(inlineRangeMatch[2]);
      if (looksLikeTocTitle(title)) {
        entries.push({
          chapterNumber: Number(inlineRangeMatch[1]),
          title,
          printedStartPage: Number(inlineRangeMatch[3]),
          confidence: 0.86,
          matchReason: "inline_range_start",
        });
      }
      continue;
    }

    if (!currentPage || countUnicodeLetters(currentLine) > 2) {
      continue;
    }
  }

  return entries;
}

function extractStandaloneStartPages(lines: string[]) {
  const rangeStarts = [...new Set(
    lines.flatMap((line) => {
      const cleaned = sanitizeTocTitle(line);
      const rangeMatch = cleaned.match(/(\d{1,3})\s*[-â€“]\s*\d{1,3}$/);
      return rangeMatch ? [Number(rangeMatch[1])] : [];
    }),
  )].sort((left, right) => left - right);
  if (rangeStarts.length >= 2) {
    return rangeStarts;
  }

  const pages = [...new Set(
    lines.flatMap((line) => {
      const cleaned = sanitizeTocTitle(line);
      if (!isStandalonePageReference(cleaned)) {
        return [];
      }

      const page = parsePrintedStartPage(cleaned);
      return page ? [page] : [];
    }),
  )].sort((left, right) => left - right);

  return pages.length >= 4 ? pages : [];
}

function extractHeadingTitleFromPage(page: ExtractedPdfPage) {
  const candidates = [...page.textBlocks]
    .sort((left, right) => left.bbox[1] - right.bbox[1] || left.bbox[0] - right.bbox[0])
    .map((block) => sanitizeTocTitle(block.text.replace(/\n+/g, " ")))
    .filter((text) => text && !/^\d{1,3}$/.test(text))
    .slice(0, 8);

  const preferred = candidates.find((text) => looksLikeTocTitle(text) && countUnicodeLetters(text) >= 8);
  if (preferred) {
    return preferred;
  }

  return candidates.find((text) => looksLikeTocTitle(text)) ?? null;
}

function extractFallbackEntriesFromCandidatePages(candidates: ExtractedPdfPage[], pages: ExtractedPdfPage[]) {
  const fallbackSourcePages = candidates.filter((page) => {
    const numericLikeLines = page.rawText
      .split("\n")
      .map((line) => sanitizeTocTitle(line))
      .filter((line) => isStandalonePageReference(line) || /(\d{1,3})\s*[-â€“]\s*\d{1,3}$/.test(line)).length;
    return numericLikeLines >= 4 || page.tocScore >= 10 || containsContentsHint(page.rawText);
  });
  const pagesToScan = fallbackSourcePages.length > 0 ? fallbackSourcePages : candidates;
  const candidateLines = pagesToScan.flatMap((page) =>
    page.rawText
      .split("\n")
      .map((line) => sanitizeTocTitle(line))
      .filter(Boolean),
  );
  const rangeEntries = extractRangeStartEntries(candidateLines);
  if (rangeEntries.length >= 2) {
    return rangeEntries;
  }

  const startPages = extractStandaloneStartPages(candidateLines);
  if (startPages.length < 4) {
    return [];
  }

  const estimatedFirstChapterPage =
    candidates.map((page) => page.pdfPageNumber).sort((left, right) => left - right)[0] ?? 1;
  const inferredOffset =
    startPages.every((page) => page > pages.length) && startPages.length > 0 ? Math.max(0, startPages[0]! - (estimatedFirstChapterPage + 2)) : 0;

  return startPages
    .map((printedStartPage, index) => {
      const approxPdfPage = Math.min(pages.length, Math.max(1, printedStartPage - inferredOffset));
      const title = extractHeadingTitleFromPage(pages[approxPdfPage - 1]!);
      if (!title) {
        return null;
      }

      return {
        chapterNumber: index + 1,
        title,
        printedStartPage,
        confidence: 0.8,
        matchReason: "fallback_start_pages_heading_title",
      };
    })
    .filter((value): value is { chapterNumber: number; title: string; printedStartPage: number; confidence: number; matchReason: string } => Boolean(value));
}

function assignSequentialChapterNumbers(
  entries: Array<Omit<ChapterIndexEntry, "chapterNumber"> & { chapterNumber?: number | null }>,
) {
  let nextChapterNumber = 1;
  return entries.map((entry) => {
    const chapterNumber = entry.chapterNumber && entry.chapterNumber > 0 ? entry.chapterNumber : nextChapterNumber;
    nextChapterNumber = Math.max(nextChapterNumber, chapterNumber + 1);
    return {
      ...entry,
      chapterNumber,
    } satisfies ChapterIndexEntry;
  });
}

function countTocLikeLines(text: string) {
  return normalizeWhitespace(text)
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .filter((line) => looksLikeTocEntryText(line)).length;
}

function scoreTitleMatch(title: string, pageText: string) {
  const titleTokens = normalizeForSearch(title).split(" ").filter((token) => token.length > 2);
  const pageTokens = new Set(normalizeForSearch(pageText).split(" ").filter(Boolean));
  const overlap = titleTokens.filter((token) => pageTokens.has(token)).length;
  return titleTokens.length ? overlap / titleTokens.length : 0;
}

function detectCaptionType(line: string): AssetType | null {
  const value = line.toLowerCase();
  if (/^table\b/.test(value)) return "table";
  if (/^(graph|chart)\b/.test(value)) return "graph";
  if (/^(figure|fig\.?|diagram)\b/.test(value)) return "diagram";
  if (/^(illustration|plate)\b/.test(value)) return "illustration";
  if (/^(image|photo|photograph)\b/.test(value)) return "image";
  return null;
}

function detectContentType(block: string, chapterNumber: number, chapterTitle: string): ContentType {
  const trimmed = block.trim();
  const normalized = normalizeForSearch(trimmed);

  if (!trimmed) return "paragraph";
  if (normalized === normalizeForSearch(chapterTitle) || normalized === normalizeForSearch(`chapter ${chapterNumber} ${chapterTitle}`)) {
    return "chapter_heading";
  }
  if (/^(summary|key points?|in short)\b/i.test(trimmed)) return "summary";
  if (/^(glossary|keywords?)\b/i.test(trimmed)) return "glossary";
  if (/^(activity)\b/i.test(trimmed)) return "activity";
  if (/^(experiment)\b/i.test(trimmed)) return "experiment";
  if (/^(exercise|let us assess|questions?)\b/i.test(trimmed)) return "exercise";
  if (/^(table)\b/i.test(trimmed)) return "table_ref";
  if (/^(graph|chart)\b/i.test(trimmed)) return "graph_ref";
  if (/^(figure|fig\.?|diagram)\b/i.test(trimmed)) return "diagram_ref";
  if (/^(definition)\b/i.test(trimmed) || /^[A-Z][A-Za-z -]{2,40}:\s+/.test(trimmed)) return "definition";
  if (/^\d+(\.\d+)+\s+/.test(trimmed)) return "section_heading";
  if (/^[A-Z][A-Z\s,-]{4,80}$/.test(trimmed) && trimmed.length < 90) return "section_heading";
  if (/^\d+[\).:-]\s+/.test(trimmed)) return "question";
  if (/^\(?[a-z]\)|^\(?[ivx]+\)/i.test(trimmed)) return "sub_question";
  if (
    /^(what|why|how|which|who|where|when|analyse|classify|correct|explain|identify|match|prepare|write|find|choose|complete|observe|list|name)\b/i.test(
      trimmed,
    ) &&
    trimmed.length < 260
  ) {
    return "question";
  }
  if (/\bformula\b|=|\btheorem\b|\blaw\b/i.test(trimmed) && trimmed.length < 200) return "formula";
  return "paragraph";
}

function sanitizeChapterEntries(entries: ChapterIndexEntry[]) {
  const filtered = entries
    .filter((entry) => entry.title && entry.printedStartPage > 0)
    .map((entry) => ({
      ...entry,
      title: sanitizeTocTitle(entry.title),
    }))
    .filter((entry) => looksLikeTocTitle(entry.title) && !isIgnoredTocTitle(entry.title))
    .sort((left, right) => left.chapterNumber - right.chapterNumber || left.printedStartPage - right.printedStartPage);
  const bestByTitle = new Map<string, ChapterIndexEntry>();

  const entryScore = (entry: ChapterIndexEntry) => {
    const normalizedTitle = normalizeForSearch(entry.title);
    const titleWordCount = normalizedTitle.split(" ").filter(Boolean).length;
    const outlierPenalty = entry.chapterNumber > Math.max(20, filtered.length + 5) ? 20 : 0;
    const titleBonus = hasEnglishTitleCaseSignal(entry.title) || !isMostlyLatinTitle(entry.title) ? 8 : 0;
    return entry.confidence * 100 + titleWordCount * 4 + titleBonus - outlierPenalty - entry.printedStartPage * 0.001;
  };

  for (const entry of filtered) {
    const titleKey = normalizeForSearch(entry.title);
    const existing = bestByTitle.get(titleKey);
    if (!existing) {
      bestByTitle.set(titleKey, entry);
      continue;
    }

    const existingScore = entryScore(existing);
    const candidateScore = entryScore(entry);

    if (
      candidateScore > existingScore ||
      (Math.abs(candidateScore - existingScore) < 0.001 && entry.printedStartPage < existing.printedStartPage)
    ) {
      bestByTitle.set(titleKey, entry);
    }
  }

  const deduped = [...bestByTitle.values()].sort(
    (left, right) => left.printedStartPage - right.printedStartPage || left.chapterNumber - right.chapterNumber,
  );
  const bestByPrintedStart = new Map<number, ChapterIndexEntry>();

  for (const entry of deduped) {
    const existing = bestByPrintedStart.get(entry.printedStartPage);
    if (!existing || entryScore(entry) > entryScore(existing)) {
      bestByPrintedStart.set(entry.printedStartPage, entry);
    }
  }

  const reduced = [...bestByPrintedStart.values()].sort(
    (left, right) => left.printedStartPage - right.printedStartPage || left.chapterNumber - right.chapterNumber,
  );
  const sequentialPairCount = reduced.filter(
    (entry, index) => index === 0 || entry.chapterNumber === reduced[index - 1]!.chapterNumber + 1,
  ).length;
  const needsSequentialRenumber =
    reduced.length >= 3 &&
    (reduced[0]!.chapterNumber !== 1 ||
      reduced.some((entry) => entry.chapterNumber > reduced.length + 3) ||
      sequentialPairCount < Math.max(2, reduced.length - 1));

  return needsSequentialRenumber
    ? reduced.map((entry, index) => ({
        ...entry,
        chapterNumber: index + 1,
      }))
    : reduced;
}

function sanitizeManualChapterInputs(entries: ManualChapterInput[]) {
  return sanitizeChapterEntries(
    entries.map((entry) => ({
      chapterNumber: entry.chapterNumber,
      title: entry.title,
      printedStartPage: entry.printedStartPage,
      pdfStartPage: entry.printedStartPage,
      confidence: 1,
      source: "manual" as const,
      matchReason: "manual_input",
    })),
  ).map((entry) => ({
    chapterNumber: entry.chapterNumber,
    title: entry.title,
    printedStartPage: entry.printedStartPage,
  }));
}

function chapterEntryQuality(entries: ChapterIndexEntry[]) {
  if (entries.length === 0) {
    return 0;
  }

  const duplicateChapterNumbers = entries.length - new Set(entries.map((entry) => entry.chapterNumber)).size;
  const alphaWeightedTitles = entries.filter((entry) => /[\p{L}\p{M}]{3,}/u.test(entry.title)).length;
  const sensiblePages = entries.filter((entry) => entry.printedStartPage > 0 && entry.printedStartPage < 500).length;
  const conciseTitles = entries.filter((entry) => entry.title.trim().length >= 3 && entry.title.trim().length <= 120).length;

  return (
    (alphaWeightedTitles / entries.length) * 0.4 +
    (sensiblePages / entries.length) * 0.2 +
    (conciseTitles / entries.length) * 0.2 +
    (duplicateChapterNumbers === 0 ? 0.2 : Math.max(0, 0.2 - duplicateChapterNumbers * 0.02))
  );
}

function shouldUseCodexFallback(entries: ChapterIndexEntry[], pageCount?: number) {
  if (entries.length < 2) {
    return true;
  }

  const orderedByPrintedPage = [...entries].sort(
    (left, right) => left.printedStartPage - right.printedStartPage || left.chapterNumber - right.chapterNumber,
  );
  const duplicateChapterNumbers = entries.length - new Set(entries.map((entry) => entry.chapterNumber)).size;
  const duplicatePrintedPages = entries.length - new Set(entries.map((entry) => entry.printedStartPage)).size;
  const maxChapterNumber = Math.max(...entries.map((entry) => entry.chapterNumber));
  const minChapterNumber = Math.min(...entries.map((entry) => entry.chapterNumber));
  const numberSpan = maxChapterNumber - minChapterNumber;
  const noisyTitles = entries.filter((entry) => /\b\d{1,3}(?:\s+\d{1,3}){1,3}$/.test(entry.title.trim())).length;
  const nonSequentialChapterNumbers = orderedByPrintedPage.filter(
    (entry, index) => index > 0 && entry.chapterNumber !== orderedByPrintedPage[index - 1]!.chapterNumber + 1,
  ).length;
  const nonIncreasingPrintedPages = orderedByPrintedPage.filter(
    (entry, index) => index > 0 && entry.printedStartPage <= orderedByPrintedPage[index - 1]!.printedStartPage,
  ).length;
  const outOfRangePrintedPages =
    pageCount && pageCount > 0
      ? entries.filter((entry) => entry.printedStartPage > pageCount * 3 || entry.printedStartPage < 1).length
      : 0;

  if (
    entries.length > 12 ||
    duplicateChapterNumbers > 0 ||
    duplicatePrintedPages > 0 ||
    maxChapterNumber > 30 ||
    numberSpan > entries.length + 10 ||
    nonSequentialChapterNumbers > 0 ||
    noisyTitles >= Math.ceil(entries.length / 2) ||
    nonIncreasingPrintedPages > 0 ||
    outOfRangePrintedPages >= Math.ceil(entries.length / 2)
  ) {
    return true;
  }

  return chapterEntryQuality(entries) < 0.7;
}

function parseChapterEntriesFromBlocks(blocks: ExtractedTextBlock[]): ChapterIndexEntry[] {
  if (blocks.length === 0) {
    return [];
  }

  const cleanedBlocks = blocks
    .map((block) => ({
      ...block,
      text: repairExtractedText(normalizeWhitespace(block.text)).replace(/[.·•…]{2,}/g, " ").trim(),
    }))
    .filter((block) => block.text.length > 0);

  const tocLikeBlockCount = cleanedBlocks.filter((block) => looksLikeTocEntryText(block.text)).length;
  const titlePageLikeBlockCount = cleanedBlocks.filter((block) => {
    const lines = block.text
      .split("\n")
      .map((line) => sanitizeTocTitle(line))
      .filter(Boolean);
    return extractTocTitlePagePairs(lines).length > 0;
  }).length;
  if (
    !cleanedBlocks.some((block) => containsContentsHint(block.text)) &&
    tocLikeBlockCount < 3 &&
    titlePageLikeBlockCount < 2
  ) {
    return [];
  }

  const numericBlocks = cleanedBlocks.filter((block) => /^\d{1,2}$/.test(block.text));
  const entries: Array<Omit<ChapterIndexEntry, "chapterNumber"> & { chapterNumber?: number | null }> = [];
  const pageLines = cleanedBlocks.flatMap((block) =>
    block.text
      .split("\n")
      .map((line) => sanitizeTocTitle(line))
      .filter(Boolean),
  );
  entries.push(
    ...extractNumberThenTitleFirstChildEntries(pageLines).map((entry) => ({
      chapterNumber: entry.chapterNumber,
      title: entry.title,
      printedStartPage: entry.printedStartPage,
      pdfStartPage: entry.printedStartPage,
      confidence: entry.confidence,
      source: "text" as const,
      matchReason: entry.matchReason,
    })),
    ...extractHierarchicalChapterEntries(pageLines).map((entry) => ({
      chapterNumber: entry.chapterNumber,
      title: entry.title,
      printedStartPage: entry.printedStartPage,
      pdfStartPage: entry.printedStartPage,
      confidence: entry.confidence,
      source: "text" as const,
      matchReason: entry.matchReason,
    })),
    ...extractSequentialTitlePageEntries(pageLines).map((entry) => ({
      chapterNumber: entry.chapterNumber,
      title: entry.title,
      printedStartPage: entry.printedStartPage,
      pdfStartPage: entry.printedStartPage,
      confidence: entry.confidence,
      source: "text" as const,
      matchReason: entry.matchReason,
    })),
  );

  for (const block of cleanedBlocks) {
    const lines = block.text
      .split("\n")
      .map((line) => sanitizeTocTitle(line))
      .filter(Boolean);
    if (lines.length === 0) continue;

    const hierarchicalEntries = extractHierarchicalChapterEntries(lines);
    if (hierarchicalEntries.length >= 2) {
      entries.push(
        ...hierarchicalEntries.map((entry) => ({
          chapterNumber: entry.chapterNumber,
          title: entry.title,
          printedStartPage: entry.printedStartPage,
          pdfStartPage: entry.printedStartPage,
          confidence: entry.confidence,
          source: "text" as const,
          matchReason: entry.matchReason,
        })),
      );
      continue;
    }

    const sequentialEntries = extractSequentialTitlePageEntries(lines);
    if (sequentialEntries.length >= 2) {
      entries.push(
        ...sequentialEntries.map((entry) => ({
          chapterNumber: entry.chapterNumber,
          title: entry.title,
          printedStartPage: entry.printedStartPage,
          pdfStartPage: entry.printedStartPage,
          confidence: entry.confidence,
          source: "text" as const,
          matchReason: entry.matchReason,
        })),
      );
      continue;
    }

    const leadingNumbers: string[] = [];
    while (leadingNumbers.length < lines.length && /^\d{1,2}$/.test(lines[leadingNumbers.length] ?? "")) {
      leadingNumbers.push(lines[leadingNumbers.length]!);
    }

    const trailingNumbers: string[] = [];
    for (let trailingIndex = lines.length - 1; trailingIndex >= 0; trailingIndex -= 1) {
      const value = lines[trailingIndex];
      if (!/^\d{1,3}$/.test(value ?? "")) {
        break;
      }
      trailingNumbers.unshift(value!);
    }

    if (leadingNumbers.length > 0 && trailingNumbers.length > 0) {
      const title = sanitizeTocTitle(
        lines.slice(leadingNumbers.length, Math.max(leadingNumbers.length, lines.length - trailingNumbers.length)).join(" "),
      );
      if (looksLikeTocTitle(title)) {
        entries.push({
          chapterNumber: Number(leadingNumbers[0]),
          title,
          printedStartPage: Number(trailingNumbers[trailingNumbers.length - 1]),
          pdfStartPage: Number(trailingNumbers[trailingNumbers.length - 1]),
          confidence: 0.98,
          source: "text",
          matchReason: "block_line_groups",
        });
        continue;
      }
    }

    const blockCenterY = (block.bbox[1] + block.bbox[3]) / 2;
    const nearestLeftChapterNumberBlock = numericBlocks
      .filter((candidate) => {
        const candidateCenterY = (candidate.bbox[1] + candidate.bbox[3]) / 2;
        return candidate.bbox[2] <= block.bbox[0] + 40 && Math.abs(candidateCenterY - blockCenterY) <= 55;
      })
      .sort((left, right) => {
        const leftDelta = Math.abs((left.bbox[1] + left.bbox[3]) / 2 - blockCenterY);
        const rightDelta = Math.abs((right.bbox[1] + right.bbox[3]) / 2 - blockCenterY);
        return leftDelta - rightDelta;
      })[0];

    if (nearestLeftChapterNumberBlock) {
      const firstLineTitlePageMatch = lines
        .map((line) => {
          const dottedMatch = line.match(/^(.+?)[.Â·â€¢â€¦]{2,}\s*(\d{1,3}(?:\s*[-â€“]\s*\d{1,3})?)$/);
          const simpleMatch = dottedMatch ?? line.match(/^(.+?)\s+(\d{1,3}(?:\s*[-â€“]\s*\d{1,3})?)$/);
          if (!simpleMatch) {
            return null;
          }
          const title = sanitizeTocTitle(simpleMatch[1]);
          const printedStartPage = parsePrintedStartPage(simpleMatch[2]);
          if (!printedStartPage || !looksLikeTocTitle(title)) {
            return null;
          }
          return { title, printedStartPage };
        })
        .find(Boolean);

      if (firstLineTitlePageMatch) {
        entries.push({
          chapterNumber: Number(nearestLeftChapterNumberBlock.text),
          title: firstLineTitlePageMatch.title,
          printedStartPage: firstLineTitlePageMatch.printedStartPage,
          pdfStartPage: firstLineTitlePageMatch.printedStartPage,
          confidence: 0.93,
          source: "text",
          matchReason: "block_left_number_first_line_title_page",
        });
        continue;
      }
    }

    if (/^\d{1,2}$/.test(lines[0] ?? "")) {
      const combinedTitleAndPage = lines.slice(1).join(" ").trim();
      const combinedMatch = combinedTitleAndPage.match(/^(.+?)\s+(\d{1,3}(?:\s*[-â€“]\s*\d{1,3})?)$/);
      const printedStartPage = parsePrintedStartPage(combinedMatch?.[2]);
      const title = sanitizeTocTitle(combinedMatch?.[1] ?? "");
      if (printedStartPage && looksLikeTocTitle(title)) {
        entries.push({
          chapterNumber: Number(lines[0]),
          title,
          printedStartPage,
          pdfStartPage: printedStartPage,
          confidence: 0.95,
          source: "text",
          matchReason: "block_number_then_title_page",
        });
        continue;
      }
    }

    const explicitMatch =
      block.text.match(/^(?:chapter|unit)?\s*(\d{1,2})[\s.:-]+(.+?)\s+(\d{1,3})$/i) ??
      block.text.match(/^(\d{1,2})\s+(.+?)\s+(\d{1,3})$/i);
    if (explicitMatch) {
      const title = sanitizeTocTitle(explicitMatch[2]);
      if (!looksLikeTocTitle(title)) continue;
      entries.push({
        chapterNumber: Number(explicitMatch[1]),
        title,
        printedStartPage: Number(explicitMatch[3]),
        pdfStartPage: Number(explicitMatch[3]),
        confidence: 0.94,
        source: "text",
        matchReason: "block_explicit",
      });
      continue;
    }

    const reversedExplicitMatch = block.text.match(/^(\d{1,3})\s+(\d{1,2})\s+(.+)$/i);
    if (reversedExplicitMatch) {
      const title = sanitizeTocTitle(reversedExplicitMatch[3]);
      const chapterNumber = Number(reversedExplicitMatch[2]);
      const printedStartPage = Number(reversedExplicitMatch[1]);
      if (!looksLikeTocTitle(title) || printedStartPage <= 0 || chapterNumber <= 0) {
        continue;
      }
      entries.push({
        chapterNumber,
        title,
        printedStartPage,
        pdfStartPage: printedStartPage,
        confidence: 0.9,
        source: "text",
        matchReason: "block_explicit_reversed",
      });
      continue;
    }

    if (lines.length === 2 && /^\d{1,2}$/.test(lines[0] ?? "") && /^\d{1,3}$/.test(lines[1] ?? "")) {
      const chapterNumber = Number(lines[0]);
      const printedStartPage = Number(lines[1]);
      const centerY = (block.bbox[1] + block.bbox[3]) / 2;
      const siblingTitleBlock = cleanedBlocks
        .filter((candidate) => candidate !== block)
        .map((candidate) => {
          const candidateCenterY = (candidate.bbox[1] + candidate.bbox[3]) / 2;
          return {
            ...candidate,
            centerYDistance: Math.abs(candidateCenterY - centerY),
          };
        })
        .filter(
          (candidate) =>
            candidate.centerYDistance <= 55 &&
            candidate.bbox[0] >= block.bbox[0] + 20 &&
            !containsContentsHint(candidate.text),
        )
        .sort((left, right) => left.centerYDistance - right.centerYDistance)[0];

      const title = sanitizeTocTitle(siblingTitleBlock?.text.split("\n").join(" ") ?? "");
      if (looksLikeTocTitle(title)) {
        entries.push({
          chapterNumber,
          title,
          printedStartPage,
          pdfStartPage: printedStartPage,
          confidence: 0.91,
          source: "text",
          matchReason: "block_numeric_pair",
        });
        continue;
      }
    }

    const inlineTitle = sanitizeTocTitle(lines.join(" "));
    if (looksLikeTocTitle(inlineTitle) && !containsContentsHint(inlineTitle)) {
      const centerY = (block.bbox[1] + block.bbox[3]) / 2;
      const leftNumberBlock = numericBlocks
        .filter((candidate) => {
          const candidateCenterY = (candidate.bbox[1] + candidate.bbox[3]) / 2;
          return candidate.bbox[2] <= block.bbox[0] + 30 && Math.abs(candidateCenterY - centerY) <= 50;
        })
        .sort((left, right) => left.bbox[0] - right.bbox[0])[0];
      const rightPageBlock = cleanedBlocks
        .filter((candidate) => candidate !== block)
        .map((candidate) => {
          const candidateCenterY = (candidate.bbox[1] + candidate.bbox[3]) / 2;
          return {
            ...candidate,
            centerYDistance: Math.abs(candidateCenterY - centerY),
            printedStartPage: parsePrintedStartPage(candidate.text),
          };
        })
        .filter(
          (candidate) =>
            candidate.printedStartPage &&
            candidate.bbox[0] >= block.bbox[2] - 10 &&
            candidate.centerYDistance <= 50,
        )
        .sort((left, right) => left.centerYDistance - right.centerYDistance)[0];

      if (leftNumberBlock && rightPageBlock?.printedStartPage) {
        entries.push({
          chapterNumber: Number(leftNumberBlock.text),
          title: inlineTitle,
          printedStartPage: rightPageBlock.printedStartPage,
          pdfStartPage: rightPageBlock.printedStartPage,
          confidence: 0.93,
          source: "text",
          matchReason: "block_three_column_pair",
        });
        continue;
      }
    }

    const trailingPageLine = lines.at(-1);
    if (!trailingPageLine || !/^\d{1,3}$/.test(trailingPageLine)) {
      continue;
    }

    const title = sanitizeTocTitle(lines.slice(0, -1).join(" "));
    if (!looksLikeTocTitle(title)) {
      continue;
    }

    const centerY = (block.bbox[1] + block.bbox[3]) / 2;
    const leftChapterNumberBlock = numericBlocks
      .filter((candidate) => {
        const candidateCenterY = (candidate.bbox[1] + candidate.bbox[3]) / 2;
        return candidate.bbox[2] <= block.bbox[0] + 40 && Math.abs(candidateCenterY - centerY) <= 45;
      })
      .sort((left, right) => {
        const leftDelta = Math.abs((left.bbox[1] + left.bbox[3]) / 2 - centerY);
        const rightDelta = Math.abs((right.bbox[1] + right.bbox[3]) / 2 - centerY);
        return leftDelta - rightDelta;
      })[0];

    if (!leftChapterNumberBlock) {
      continue;
    }

    entries.push({
      chapterNumber: Number(leftChapterNumberBlock.text),
      title,
      printedStartPage: Number(trailingPageLine),
      pdfStartPage: Number(trailingPageLine),
      confidence: 0.97,
      source: "text",
      matchReason: "block_pairing",
    });
  }

  const columnGroupEntries: Array<Omit<ChapterIndexEntry, "chapterNumber"> & { chapterNumber?: number | null }> = [];
  if (numericBlocks.length >= 3) {
    const maxX = cleanedBlocks.reduce((value, block) => Math.max(value, block.bbox[2]), 0);
    const midX = maxX / 2;
    const numberedColumns = numericBlocks
      .map((block) => ({
        block,
        chapterNumber: Number(block.text),
        column: (block.bbox[0] + block.bbox[2]) / 2 < midX ? "left" : "right",
        centerY: (block.bbox[1] + block.bbox[3]) / 2,
      }))
      .sort((left, right) => left.centerY - right.centerY || left.chapterNumber - right.chapterNumber);
    const titleBlocks = cleanedBlocks
      .filter((block) => !/^\d{1,2}$/.test(block.text))
      .flatMap((block) => {
        const lines = block.text
          .split("\n")
          .map((line) => sanitizeTocTitle(line))
          .filter(Boolean);
        const firstPair = extractTocTitlePagePairs(lines)[0];
        if (!firstPair) {
          return [];
        }

        return [
          {
            block,
            column: (block.bbox[0] + block.bbox[2]) / 2 < midX ? "left" : "right",
            title: firstPair.title,
            printedStartPage: firstPair.printedStartPage,
          },
        ];
      });

    for (const numbered of numberedColumns) {
      const nextSameColumn = numberedColumns.find(
        (candidate) => candidate.column === numbered.column && candidate.centerY > numbered.centerY,
      );
      const match = titleBlocks
        .filter(
          (candidate) =>
            candidate.column === numbered.column &&
            candidate.block.bbox[1] >= numbered.block.bbox[3] - 8 &&
            candidate.block.bbox[1] < (nextSameColumn?.block.bbox[1] ?? Number.POSITIVE_INFINITY) - 6,
        )
        .sort(
          (left, right) =>
            left.block.bbox[1] - right.block.bbox[1] ||
            Math.abs(left.block.bbox[0] - numbered.block.bbox[0]) -
              Math.abs(right.block.bbox[0] - numbered.block.bbox[0]),
        )[0];

      if (!match) {
        continue;
      }

      columnGroupEntries.push({
        chapterNumber: numbered.chapterNumber,
        title: match.title,
        printedStartPage: match.printedStartPage,
        pdfStartPage: match.printedStartPage,
        confidence: 0.9,
        source: "text",
        matchReason: "block_column_group_first_title",
      });
    }
  }

  const sanitizedEntries = sanitizeChapterEntries(assignSequentialChapterNumbers(entries));
  const sanitizedColumnGroupEntries = sanitizeChapterEntries(assignSequentialChapterNumbers(columnGroupEntries));

  if (
    sanitizedColumnGroupEntries.length >= 3 &&
    sanitizedColumnGroupEntries.length > sanitizedEntries.length &&
    chapterEntryQuality(sanitizedColumnGroupEntries) >= chapterEntryQuality(sanitizedEntries)
  ) {
    return sanitizedColumnGroupEntries;
  }

  return sanitizedEntries;
}

function parseChapterEntriesFromText(text: string): ChapterIndexEntry[] {
  const lines = normalizeWhitespace(text)
    .split("\n")
    .map((line) => line.replace(/[.·•…]{2,}/g, " ").trim())
    .filter(Boolean);

  const hasContentsHint = lines.some((line) => containsContentsHint(line));
  const hasLeadingContentsHint = lines.slice(0, 5).some((line) => containsContentsHint(line));
  const tocLikeLineCount = lines.filter((line) => looksLikeTocEntryText(line)).length;
  const allowTocParsing = hasLeadingContentsHint || tocLikeLineCount >= 3;
  const entries: Array<Omit<ChapterIndexEntry, "chapterNumber"> & { chapterNumber?: number | null }> = [];
  if (allowTocParsing || hasContentsHint) {
    entries.push(
      ...extractNumberThenTitleFirstChildEntries(lines).map((entry) => ({
        chapterNumber: entry.chapterNumber,
        title: entry.title,
        printedStartPage: entry.printedStartPage,
        pdfStartPage: entry.printedStartPage,
        confidence: entry.confidence,
        source: "text" as const,
        matchReason: entry.matchReason,
      })),
      ...extractHierarchicalChapterEntries(lines).map((entry) => ({
        chapterNumber: entry.chapterNumber,
        title: entry.title,
        printedStartPage: entry.printedStartPage,
        pdfStartPage: entry.printedStartPage,
        confidence: entry.confidence,
        source: "text" as const,
        matchReason: entry.matchReason,
      })),
      ...extractSequentialTitlePageEntries(lines).map((entry) => ({
        chapterNumber: entry.chapterNumber,
        title: entry.title,
        printedStartPage: entry.printedStartPage,
        pdfStartPage: entry.printedStartPage,
        confidence: entry.confidence,
        source: "text" as const,
        matchReason: entry.matchReason,
      })),
    );
  }
  if (allowTocParsing) {
    for (let index = 0; index < lines.length; index += 1) {
      const chapterNumberLine = lines[index];
      const titleLine = lines[index + 1];
      const printedPageLine = lines[index + 2];
      const nextLineStartPage = parsePrintedStartPage(titleLine);
      const printedStartPage = parsePrintedStartPage(printedPageLine);

      if (
        /^\d{1,2}$/.test(chapterNumberLine) &&
        titleLine &&
        looksLikeTocTitle(titleLine) &&
        printedStartPage
      ) {
        entries.push({
          chapterNumber: Number(chapterNumberLine),
          title: sanitizeTocTitle(titleLine),
          printedStartPage,
          pdfStartPage: printedStartPage,
          confidence: 0.92,
          source: "text",
          matchReason: "stacked_lines",
        });
        index += 2;
        continue;
      }

      const chapterNumberTitleMatch = chapterNumberLine?.match(/^(\d{1,2})[.\s:-]+(.+)$/);
      if (hasLeadingContentsHint && chapterNumberTitleMatch && nextLineStartPage) {
        const extractedTitle = sanitizeTocTitle(chapterNumberTitleMatch[2]);
        if (!looksLikeTocTitle(extractedTitle)) {
          continue;
        }
        entries.push({
          chapterNumber: Number(chapterNumberTitleMatch[1]),
          title: extractedTitle,
          printedStartPage: nextLineStartPage,
          pdfStartPage: nextLineStartPage,
          confidence: 0.88,
          source: "text",
          matchReason: "title_with_number_then_page",
        });
        index += 1;
        continue;
      }

      if (
        hasLeadingContentsHint &&
        titleLine &&
        nextLineStartPage &&
        looksLikeTocTitle(chapterNumberLine) &&
        !containsContentsHint(chapterNumberLine)
      ) {
        entries.push({
          chapterNumber: undefined,
          title: sanitizeTocTitle(chapterNumberLine),
          printedStartPage: nextLineStartPage,
          pdfStartPage: nextLineStartPage,
          confidence: 0.74,
          source: "text",
          matchReason: "title_page_pair",
        });
        index += 1;
      }
    }
  }

  if (allowTocParsing) {
    for (const line of lines) {
      const explicitMatch =
        line.match(/^(?:chapter|unit)?\s*(\d{1,2})[\s.:-]+(.+?)\s+(\d{1,3}(?:\s*[-–]\s*\d{1,3})?)$/i) ??
        line.match(/^(\d{1,2})\s+(.+?)\s+(\d{1,3}(?:\s*[-–]\s*\d{1,3})?)$/i);
      if (explicitMatch) {
        const title = sanitizeTocTitle(explicitMatch[2]);
        const printedStartPage = parsePrintedStartPage(explicitMatch[3]);
        if (!looksLikeTocTitle(title)) continue;
        if (!printedStartPage) continue;
        entries.push({
          chapterNumber: Number(explicitMatch[1]),
          title,
          printedStartPage,
          pdfStartPage: printedStartPage,
          confidence: 0.78,
          source: "text",
          matchReason: "regex_explicit",
        });
      }
    }
  }

  return sanitizeChapterEntries(assignSequentialChapterNumbers(entries));
}

function isLikelyContentsPage(page: ExtractedPdfPage) {
  const blockEntries = parseChapterEntriesFromBlocks(page.textBlocks);
  if (blockEntries.length >= 2) {
    return true;
  }

  const tocLikeLineCount = countTocLikeLines(page.rawText);
  const numericLineCount = page.rawText
    .split("\n")
    .map((line) => sanitizeTocTitle(line))
    .filter((line) => isStandalonePageReference(line) || /^\d{1,2}[.\s:-]+/.test(line)).length;

  return (containsContentsHint(page.rawText) && (page.tocScore >= 3 || numericLineCount >= 3)) || tocLikeLineCount >= 3;
}

async function findChromePath(overridePath?: string) {
  const candidates = [
    overridePath,
    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
    "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
  ].filter(Boolean) as string[];

  for (const candidate of candidates) {
    try {
      await readFile(candidate);
      return candidate;
    } catch {
      // Ignore missing browser candidates.
    }
  }

  return null;
}

async function renderPdfPageImage(params: {
  pdfPath: string;
  pageNumber: number;
  outputPath: string;
  chromePath?: string;
}) {
  try {
    await execFileAsync(
      "python",
      [
        "-c",
        [
          "import fitz",
          `pdf = fitz.open(r'''${params.pdfPath}''')`,
          `page = pdf.load_page(${params.pageNumber - 1})`,
          "pix = page.get_pixmap(matrix=fitz.Matrix(2, 2), alpha=False)",
          `pix.save(r'''${params.outputPath}''')`,
        ].join("; "),
      ],
      {
        windowsHide: true,
        timeout: 30_000,
        maxBuffer: 8 * 1024 * 1024,
      },
    );
    return params.outputPath;
  } catch {
    // Fall through to the browser-based renderer if PyMuPDF is unavailable.
  }

  const chromePath = await findChromePath(params.chromePath);
  if (!chromePath) {
    throw new Error("Chrome or Edge was not found for PDF page screenshot rendering.");
  }

  await mkdir(path.dirname(params.outputPath), { recursive: true });

  const pdfUrl = `file:///${path.resolve(params.pdfPath).replace(/\\/g, "/")}#page=${params.pageNumber}`;
  await execFileAsync(
    chromePath,
    [
      "--headless=new",
      "--disable-gpu",
      "--hide-scrollbars",
      "--run-all-compositor-stages-before-draw",
      "--virtual-time-budget=2000",
      "--window-size=1600,2200",
      `--screenshot=${params.outputPath}`,
      pdfUrl,
    ],
    {
      windowsHide: true,
      timeout: 30_000,
      maxBuffer: 8 * 1024 * 1024,
    },
  );

  return params.outputPath;
}

function extractJsonObject(input: string) {
  const fencedMatch = input.match(/```json\s*([\s\S]*?)```/i);
  if (fencedMatch) {
    return fencedMatch[1].trim();
  }

  const objectMatch = input.match(/\{[\s\S]*\}/);
  if (objectMatch) {
    return objectMatch[0];
  }

  return input.trim();
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

function getChapterWorkerCount(chapterCount: number) {
  const override = Number(process.env.RIGHT_ANSWER_TEXTBOOK_CHAPTER_WORKERS ?? "");
  if (Number.isFinite(override) && override > 0) {
    return Math.max(1, Math.min(chapterCount, Math.floor(override)));
  }
  const availableCpus = os.cpus()?.length ?? 4;
  return Math.max(1, Math.min(chapterCount, availableCpus - 2));
}

function getOcrWorkerCount(pageCount: number) {
  const override = Number(process.env.RIGHT_ANSWER_TEXTBOOK_OCR_WORKERS ?? "");
  if (Number.isFinite(override) && override > 0) {
    return Math.max(1, Math.min(pageCount, Math.floor(override)));
  }
  return 1;
}

function truncateText(text: string, maxLength: number) {
  const cleaned = normalizeWhitespace(text).replace(/\s+/g, " ").trim();
  if (cleaned.length <= maxLength) {
    return cleaned;
  }
  return `${cleaned.slice(0, Math.max(0, maxLength - 1)).trim()}...`;
}

function splitIntoSentences(text: string) {
  return repairExtractedText(text)
    .split(/(?<=[.!?])\s+|\n+/)
    .map((sentence) => truncateText(sentence, 220))
    .filter((sentence) => sentence.length >= 25);
}

function uniqueStrings(values: string[]) {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    const key = normalizeForSearch(value);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(value);
  }
  return result;
}

function buildChapterSummaryArtifact(params: {
  chapter: ChapterIndexEntry;
  pageArtifacts: Array<Record<string, unknown>>;
  contentUnits: StructuredContentUnit[];
  assets: DetectedAsset[];
  questions: StructuredQuestionRecord[];
}) {
  const sectionHeadings = uniqueStrings(
    params.contentUnits
      .filter((unit) => unit.contentType === "section_heading" || unit.contentType === "chapter_heading")
      .map((unit) => truncateText(unit.text, 120)),
  ).slice(0, 12);

  const candidateSummaryTexts = uniqueStrings(
    params.contentUnits
      .filter((unit) =>
        unit.contentType === "paragraph" ||
        unit.contentType === "definition" ||
        unit.contentType === "formula" ||
        unit.contentType === "summary",
      )
      .flatMap((unit) => splitIntoSentences(unit.text)),
  );

  const keyPoints = candidateSummaryTexts.slice(0, 8);
  const summaryText = keyPoints.slice(0, 4).join(" ");

  const importantQuestions = uniqueStrings(
    params.questions.map((question) => truncateText(question.questionText, 220)),
  ).slice(0, 10);

  const contentTypeCounts = Object.fromEntries(
    Array.from(
      params.contentUnits.reduce((accumulator, unit) => {
        accumulator.set(unit.contentType, (accumulator.get(unit.contentType) ?? 0) + 1);
        return accumulator;
      }, new Map<string, number>()),
    ).sort(([left], [right]) => left.localeCompare(right)),
  );

  const assetTypeCounts = Object.fromEntries(
    Array.from(
      params.assets.reduce((accumulator, asset) => {
        accumulator.set(asset.assetType, (accumulator.get(asset.assetType) ?? 0) + 1);
        return accumulator;
      }, new Map<string, number>()),
    ).sort(([left], [right]) => left.localeCompare(right)),
  );

  return {
    chapterNumber: params.chapter.chapterNumber,
    title: params.chapter.title,
    printedStartPage: params.chapter.printedStartPage,
    pdfStartPage: params.chapter.pdfStartPage,
    pdfEndPage: params.chapter.pdfEndPage,
    confidence: params.chapter.confidence,
    source: params.chapter.source,
    matchReason: params.chapter.matchReason,
    pageCount: params.pageArtifacts.length,
    contentUnitCount: params.contentUnits.length,
    assetCount: params.assets.length,
    questionCount: params.questions.length,
    sectionHeadings,
    keyPoints,
    summaryText,
    importantQuestions,
    contentTypeCounts,
    assetTypeCounts,
  };
}

async function removeStorageVersionFolder(params: {
  rootPath: string;
  subjectCode: string;
  medium: Medium;
  versionLabel: string;
  kind: "raw" | "processed";
}) {
  const baseRoot = path.resolve(params.rootPath);
  const targetPath = path.resolve(
    baseRoot,
    buildTextbookStorageKey({
      syllabus: "sslc",
      subjectSlug: params.subjectCode,
      medium: params.medium,
      versionLabel: params.versionLabel,
      kind: params.kind,
      fileName: "",
    }),
  );
  const relativeTarget = path.relative(baseRoot, targetPath);

  if (
    !relativeTarget ||
    relativeTarget.startsWith("..") ||
    path.isAbsolute(relativeTarget) ||
    relativeTarget.split(path.sep).length < 5
  ) {
    throw new Error(`Refusing to delete unsafe storage path: ${targetPath}`);
  }

  await rm(targetPath, { recursive: true, force: true });
}

async function clearVersionStorage(params: {
  subjectCode: string;
  medium: Medium;
  versionLabel: string;
}) {
  const storageRootPath = path.resolve(process.cwd(), STORAGE_ROOT);
  await removeStorageVersionFolder({
    rootPath: storageRootPath,
    subjectCode: params.subjectCode,
    medium: params.medium,
    versionLabel: params.versionLabel,
    kind: "raw",
  });
  await removeStorageVersionFolder({
    rootPath: storageRootPath,
    subjectCode: params.subjectCode,
    medium: params.medium,
    versionLabel: params.versionLabel,
    kind: "processed",
  });
}

async function detectChaptersWithCodex(params: {
  pdfPath: string;
  candidatePages: ExtractedPdfPage[];
  outputDir: string;
  chromePath?: string;
}) {
  const codexConcurrencyLimit = Math.max(
    1,
    Math.min(2, Number(process.env.RIGHT_ANSWER_CODEX_TOC_WORKERS ?? "2") || 2),
  );
  const semaphoreState = (globalThis as typeof globalThis & {
    __rightAnswerCodexTocSemaphore?: { active: number; waiters: Array<() => void> };
  }).__rightAnswerCodexTocSemaphore ?? { active: 0, waiters: [] as Array<() => void> };
  (globalThis as typeof globalThis & {
    __rightAnswerCodexTocSemaphore?: { active: number; waiters: Array<() => void> };
  }).__rightAnswerCodexTocSemaphore = semaphoreState;

  const withCodexTocSlot = async <T>(task: () => Promise<T>) => {
    if (semaphoreState.active >= codexConcurrencyLimit) {
      await new Promise<void>((resolve) => {
        semaphoreState.waiters.push(resolve);
      });
    }

    semaphoreState.active += 1;
    try {
      return await task();
    } finally {
      semaphoreState.active = Math.max(0, semaphoreState.active - 1);
      semaphoreState.waiters.shift()?.();
    }
  };

  const codexBinary = "C:\\Users\\razin\\AppData\\Local\\Programs\\OpenAI\\Codex\\bin\\codex.exe";
  const notes: string[] = [];
  const selectedPages = params.candidatePages.slice(0, 4);
  const pageTextContext = selectedPages
    .map((page) => {
      const snippet = page.rawText
        .split("\n")
        .map((line) => line.trim())
        .filter(Boolean)
        .slice(0, 40)
        .join("\n")
        .slice(0, 3000);
      return [`Page ${page.pdfPageNumber}:`, snippet || "[no extracted text]"].join("\n");
    })
    .join("\n\n---\n\n");
  const hasUsefulExtractedText =
    selectedPages.filter((page) => page.rawText.trim().length >= 40).length >= 2 &&
    countUnicodeLetters(pageTextContext) >= 10;
  const mostlyNumericOcrPages =
    selectedPages.filter(
      (page) =>
        page.ocrUsed &&
        page.charCount > 0 &&
        ((page.rawText.match(/\d/g) ?? []).length / Math.max(1, page.rawText.length) >= 0.35 ||
          countUnicodeLetters(page.rawText) < 20),
    ).length >= Math.max(1, Math.ceil(selectedPages.length / 2));

  const runCodexPrompt = async (prompt: string, imagePaths: string[], attemptLabel: string, timeout: number) => {
    const outputFile = path.join(params.outputDir, `codex-toc-output-${attemptLabel}.json`);
    const parsedPayload = await withCodexTocSlot(async () => {
      let lastError: unknown;
      for (let attempt = 1; attempt <= 2; attempt += 1) {
        try {
          await execFileAsync(
            codexBinary,
            [
              "exec",
              "--skip-git-repo-check",
              "--ignore-rules",
              "--output-last-message",
              outputFile,
              ...imagePaths.flatMap((imagePath) => ["--image", imagePath]),
              prompt,
            ],
            {
              windowsHide: true,
              timeout,
              maxBuffer: 16 * 1024 * 1024,
            },
          );
          const outputText = await readFile(outputFile, "utf8");
          return JSON.parse(extractJsonObject(outputText)) as {
            chapters?: Array<{ chapterNumber: number; title: string; printedStartPage: number }>;
            notes?: string[];
          };
        } catch (error) {
          lastError = error;
          notes.push(`${attemptLabel}_attempt_${attempt}_failed`);
        }
      }
      throw lastError instanceof Error ? lastError : new Error(`Codex TOC detection failed (${attemptLabel}).`);
    });

    notes.push(...(parsedPayload.notes ?? []).map((note) => String(note)));
    return sanitizeChapterEntries(
      (parsedPayload.chapters ?? []).map((chapter) => ({
        chapterNumber: Number(chapter.chapterNumber),
        title: String(chapter.title ?? "").trim(),
        printedStartPage: Number(chapter.printedStartPage),
        pdfStartPage: Number(chapter.printedStartPage),
        confidence: 0.9,
        source: "codex",
        matchReason: "codex_vision",
      })),
    );
  };

  if (hasUsefulExtractedText && !mostlyNumericOcrPages) {
    const textOnlyPrompt = [
      "You are extracting a textbook table of contents from OCR/extracted text of textbook pages.",
      "Return JSON only with this exact shape:",
      '{ "chapters": [ { "chapterNumber": 1, "title": "Life Processes", "printedStartPage": 12 } ], "notes": ["optional"] }',
      "Rules:",
      "- Only include real chapter entries, not front matter.",
      "- Preserve titles exactly as seen in the extracted text, including native script.",
      "- printedStartPage must be an integer.",
      "- Sort chapters by chapterNumber ascending.",
      "- If a line shows a page range like 137-150, use the first value as printedStartPage.",
      "- Ignore publisher pages, preface, glossary, and answer keys unless they are clearly part of the chapter list.",
      "- If uncertain, still return your best structured guess.",
      "",
      "Extracted page text:",
      pageTextContext,
    ].join("\n");

    try {
      const textEntries = await runCodexPrompt(textOnlyPrompt, [], "text", 90_000);
      if (textEntries.length >= 2 && !shouldUseCodexFallback(textEntries)) {
        return { entries: textEntries, notes };
      }
    } catch (error) {
      notes.push(error instanceof Error ? error.message : String(error));
    }
  }

  const imagePaths: string[] = [];
  for (const page of selectedPages) {
    const imagePath = path.join(params.outputDir, `toc-page-${String(page.pdfPageNumber).padStart(3, "0")}.png`);
    await renderPdfPageImage({
      pdfPath: params.pdfPath,
      pageNumber: page.pdfPageNumber,
      outputPath: imagePath,
      chromePath: params.chromePath,
    });
    imagePaths.push(imagePath);
  }
  const visionPrompt = [
    "You are extracting a textbook table of contents from attached page images.",
    "Use both the attached images and the extracted page text below.",
    "Return JSON only with this exact shape:",
    '{ "chapters": [ { "chapterNumber": 1, "title": "Life Processes", "printedStartPage": 12 } ], "notes": ["optional"] }',
    "Rules:",
    "- Only include real chapter entries, not front matter.",
    "- Preserve titles exactly as seen, including native script.",
    "- printedStartPage must be an integer.",
    "- Sort chapters by chapterNumber ascending.",
    "- If a page shows a page range like 137-150, use the first value as printedStartPage.",
    "- Ignore publisher pages, preface, glossary, and answer keys unless they are clearly part of the chapter list.",
    "- If uncertain, still return your best structured guess.",
    "",
    "Extracted page text:",
    pageTextContext,
  ].join("\n");

  return {
    entries: await runCodexPrompt(visionPrompt, imagePaths, "vision", 120_000),
    notes,
  };
}

function resolveChapterStartPages(
  entries: ChapterIndexEntry[],
  pages: ExtractedPdfPage[],
  inferredPrintedPageOffset = 0,
) {
  const sortedEntries = [...entries].sort(
    (left, right) => left.printedStartPage - right.printedStartPage || left.chapterNumber - right.chapterNumber,
  );
  let minimumSearchPage = 1;

  return sortedEntries.map((entry) => {
    const expectedPrintedStartPage = Math.max(1, entry.printedStartPage - inferredPrintedPageOffset);
    const printedStartInPdfRange = expectedPrintedStartPage >= 1 && expectedPrintedStartPage <= pages.length;
    if (entry.source === "manual" && printedStartInPdfRange) {
      minimumSearchPage = Math.max(minimumSearchPage, expectedPrintedStartPage);
      return {
        ...entry,
        pdfStartPage: expectedPrintedStartPage,
        confidence: Math.max(entry.confidence, 1),
        matchReason: "manual_input",
      };
    }
    const printedStartPage = printedStartInPdfRange ? expectedPrintedStartPage : minimumSearchPage;
    const printedStartScore = printedStartInPdfRange
      ? scoreTitleMatch(entry.title, pages[printedStartPage - 1]?.rawText ?? "")
      : 0;

    const windowStart = printedStartInPdfRange ? Math.max(minimumSearchPage, expectedPrintedStartPage - 6) : minimumSearchPage;
    const windowEnd = printedStartInPdfRange ? Math.min(pages.length, expectedPrintedStartPage + 8) : pages.length;
    let bestPage = printedStartPage;
    let bestScore = printedStartScore;
    let bestAdjustedScore = Number.NEGATIVE_INFINITY;

    for (let pageNumber = windowStart; pageNumber <= windowEnd; pageNumber += 1) {
      const page = pages[pageNumber - 1];
      const titleScore = scoreTitleMatch(entry.title, page?.rawText ?? "");
      const tocPenalty =
        page && (containsContentsHint(page.rawText) || countTocLikeLines(page.rawText) >= 3) ? 0.45 : 0;
      const distancePenalty = printedStartInPdfRange
        ? Math.abs(pageNumber - expectedPrintedStartPage) * 0.02
        : Math.max(0, pageNumber - minimumSearchPage) * 0.003;
      const adjustedScore = titleScore - tocPenalty - distancePenalty;

      if (
        adjustedScore > bestAdjustedScore ||
        (Math.abs(adjustedScore - bestAdjustedScore) < 0.0001 &&
          Math.abs(pageNumber - printedStartPage) < Math.abs(bestPage - printedStartPage))
      ) {
        bestAdjustedScore = adjustedScore;
        bestScore = titleScore;
        bestPage = pageNumber;
      }
    }

    const bestPageLooksLikeToc =
      countTocLikeLines(pages[Math.max(0, bestPage - 1)]?.rawText ?? "") >= 3;
    const preferExpectedPrintedStart =
      inferredPrintedPageOffset > 0 &&
      printedStartInPdfRange &&
      bestPage < printedStartPage &&
      bestPageLooksLikeToc;

    const resolvedStartPage = preferExpectedPrintedStart
      ? printedStartPage
      : printedStartScore >= 0.35
        ? printedStartPage
        : bestScore >= 0.3
          ? bestPage
          : printedStartPage;
    minimumSearchPage = Math.max(minimumSearchPage, resolvedStartPage);

    return {
      ...entry,
      pdfStartPage: resolvedStartPage,
      confidence: Math.max(entry.confidence, bestScore ? Number((0.7 + bestScore * 0.3).toFixed(2)) : entry.confidence),
      matchReason:
        printedStartInPdfRange && resolvedStartPage === printedStartPage && printedStartScore >= 0.35
          ? "printed_start_title_match"
          : bestScore >= 0.3
            ? "title_match_window"
            : entry.matchReason,
    };
  });
}

function finalizeChapterRanges(entries: ChapterIndexEntry[], pageCount: number) {
  const sorted = [...entries].sort((left, right) => left.pdfStartPage - right.pdfStartPage);
  const withFrontMatter =
    sorted[0] && sorted[0].pdfStartPage > 1
      ? [
          {
            chapterNumber: 0,
            title: "Front Matter",
            printedStartPage: 1,
            pdfStartPage: 1,
            pdfEndPage: sorted[0].pdfStartPage - 1,
            confidence: 1,
            source: "text" as const,
            matchReason: "synthetic_front_matter",
          },
          ...sorted,
        ]
      : sorted;

  return withFrontMatter.map((entry, index) => ({
    ...entry,
    pdfEndPage: withFrontMatter[index + 1]?.pdfStartPage
      ? withFrontMatter[index + 1].pdfStartPage - 1
      : pageCount,
  }));
}

function mapPageToChapter(pageNumber: number, chapters: ChapterIndexEntry[]) {
  return chapters.find((chapter) => pageNumber >= chapter.pdfStartPage && pageNumber <= (chapter.pdfEndPage ?? pageNumber));
}

function stripPageNoise(block: string, pageNumber: number, chapterTitle: string) {
  const lines = repairExtractedText(block)
    .split("\n")
    .map((line) => normalizeWhitespace(line).trim())
    .filter(Boolean)
    .filter((line) => {
      const normalized = normalizeForSearch(line);
      if (!normalized) return false;
      if (normalized === String(pageNumber)) return false;
      if (/^[a-z]+ ?- ?x$/i.test(line)) return false;
      if (normalized === normalizeForSearch(chapterTitle)) return false;
      return true;
    });

  return lines.join("\n").trim();
}

function looksLikeContinuationBlock(current: string, previous: string | undefined) {
  if (!previous || !current) return false;
  if (/^(table|graph|chart|figure|fig\.?|diagram|illustration|photo)\b/i.test(current)) return false;
  if (/^\d+[\).:-]\s*/.test(current)) return false;
  if (/^\(?[a-z]\)|^\(?[ivx]+\)/i.test(current)) return false;

  const normalizedCurrent = normalizeWhitespace(current);
  const firstChar = normalizedCurrent[0] ?? "";
  if (normalizedCurrent.length <= 40) {
    return true;
  }

  return /[a-z(]/.test(firstChar) && !/[.?!:]$/.test(previous);
}

function mergeContinuationBlocks(blocks: string[]) {
  const merged: string[] = [];
  for (const block of blocks) {
    if (looksLikeContinuationBlock(block, merged[merged.length - 1])) {
      merged[merged.length - 1] = `${merged[merged.length - 1]} ${block}`.trim();
      continue;
    }
    merged.push(block);
  }
  return merged;
}

function splitCompositeBlock(block: string) {
  const trimmed = block.trim();
  const numberedMatches = trimmed.match(/^\d+[\).:-]\s+/gm) ?? [];
  if (numberedMatches.length >= 2) {
    return trimmed
      .split(/(?=^\d+[\).:-]\s+)/gm)
      .map((entry) => entry.trim())
      .filter(Boolean);
  }

  return [trimmed];
}

function splitPageIntoBlocks(page: ExtractedPdfPage, chapter: ChapterIndexEntry) {
  const baseBlocks =
    page.textBlocks.length > 0
      ? page.textBlocks
          .filter((block) => block.blockType === 0)
          .map((block) => stripPageNoise(block.text, page.pdfPageNumber, chapter.title))
          .filter(Boolean)
      : normalizeWhitespace(repairExtractedText(page.rawText))
          .replace(/\n{3,}/g, "\n\n")
          .split(/\n{2,}/)
          .map((block) => stripPageNoise(block, page.pdfPageNumber, chapter.title))
          .filter(Boolean);

  return mergeContinuationBlocks(baseBlocks)
    .flatMap((block) => splitCompositeBlock(block))
    .map((block) => block.trim())
    .filter(Boolean);
}

function looksTabular(block: string) {
  const lines = block.split("\n").map((line) => line.trim()).filter(Boolean);
  if (lines.length < 2) return false;
  const spacedRows = lines.filter((line) => / {2,}|\t|\|/.test(line)).length;
  return spacedRows >= Math.max(2, Math.floor(lines.length / 2));
}

function parseTableRows(block: string) {
  const lines = block.split("\n").map((line) => line.trim()).filter(Boolean);
  const rows = lines.map((line) =>
    line
      .split(/\s{2,}|\t|\|/)
      .map((cell) => cell.trim())
      .filter(Boolean),
  );
  const [header = [], ...rest] = rows;
  return {
    headers: header,
    rows: rest.map((cells) => Object.fromEntries(header.map((title, index) => [title || `column_${index + 1}`, cells[index] ?? ""]))),
  };
}

function detectPageAssets(params: {
  page: ExtractedPdfPage;
  blocks: string[];
  chapter: ChapterIndexEntry;
  pageImagePath: string;
  nearbyContentLocalIds: string[];
}) {
  const detected: Array<Omit<DetectedAsset, "localId" | "nearbyContentLocalIds"> & { kind: AssetType }> = [];

  for (let index = 0; index < params.blocks.length; index += 1) {
    const block = params.blocks[index];
    const firstLine = block.split("\n")[0]?.trim() ?? "";
    const captionType = detectCaptionType(firstLine);
    if (!captionType && !looksTabular(block)) {
      continue;
    }

    const kind = captionType ?? "table";
    detected.push({
      kind,
      assetType: kind,
      pageNumber: params.page.pdfPageNumber,
      captionText: firstLine,
      rawText: kind === "table" ? block : undefined,
      filePath: params.pageImagePath,
      metadata: {
        chapterTitle: params.chapter.title,
        chapterNumber: params.chapter.chapterNumber,
        blockIndex: index,
      },
    });
  }

  return detected.map((asset, index) => ({
    localId: `${asset.kind}_${params.page.pdfPageNumber}_${index + 1}`,
    assetType: asset.assetType,
    pageNumber: asset.pageNumber,
    captionText: asset.captionText,
    rawText: asset.rawText,
    filePath: asset.filePath,
    nearbyContentLocalIds: params.nearbyContentLocalIds,
    metadata: asset.metadata,
  }));
}

async function extractEmbeddedAssetsForPage(params: {
  pdfPath: string;
  page: ExtractedPdfPage;
  chapter: ChapterIndexEntry;
  embeddedAssetsDir: string;
  embeddedAssetsPrefix: string;
  nearbyContentLocalIds: string[];
}) {
  if (params.page.embeddedImageCount <= 0) {
    return [];
  }

  await mkdir(params.embeddedAssetsDir, { recursive: true });

  const { stdout } = await execFileAsync(
    "python",
    [
      "-c",
      [
        "import json, os, fitz",
        `pdf = fitz.open(r'''${params.pdfPath}''')`,
        `page = pdf.load_page(${params.page.pdfPageNumber - 1})`,
        "items = []",
        `output_dir = r'''${params.embeddedAssetsDir}'''`,
        "os.makedirs(output_dir, exist_ok=True)",
        "for info in page.get_image_info(xrefs=True):",
        "    bbox = info.get('bbox')",
        "    width = int(info.get('width', 0) or 0)",
        "    height = int(info.get('height', 0) or 0)",
        "    if not bbox or width < 60 or height < 60 or width * height < 8000:",
        "        continue",
        "    xref = int(info.get('xref', 0) or 0)",
        "    ext = 'png'",
        "    output_path = ''",
        "    if xref > 0:",
        "        extracted = pdf.extract_image(xref)",
        "        ext = extracted.get('ext', 'png')",
        `        output_path = os.path.join(output_dir, f\"page-${String(params.page.pdfPageNumber).padStart(3, "0")}-embedded-{len(items) + 1:02d}.{ext}\")`,
        "        with open(output_path, 'wb') as handle:",
        "            handle.write(extracted['image'])",
        "    items.append({",
        "        'bbox': [float(bbox[0]), float(bbox[1]), float(bbox[2]), float(bbox[3])],",
        "        'width': width,",
        "        'height': height,",
        "        'xref': xref,",
        "        'outputPath': output_path,",
        "        'ext': ext,",
        "    })",
        "print(json.dumps({'items': items}, ensure_ascii=False))",
      ].join("\n"),
    ],
    {
      windowsHide: true,
      timeout: 120_000,
      maxBuffer: 32 * 1024 * 1024,
    },
  );

  const payload = JSON.parse(stdout) as {
    items?: Array<{
      bbox: [number, number, number, number];
      width: number;
      height: number;
      xref: number;
      outputPath: string;
      ext: string;
    }>;
  };

  const captionCandidates = params.page.textBlocks
    .filter((block) => block.blockType === 0)
    .map((block) => ({
      text: stripPageNoise(block.text, params.page.pdfPageNumber, params.chapter.title),
      bbox: block.bbox,
    }))
    .filter((block) => block.text.length > 0);

  return (payload.items ?? []).map((item, index) => {
    const imageCenterY = (item.bbox[1] + item.bbox[3]) / 2;
    const nearestCaption = captionCandidates
      .map((candidate) => {
        const candidateCenterY = (candidate.bbox[1] + candidate.bbox[3]) / 2;
        return {
          ...candidate,
          distance: Math.abs(candidateCenterY - imageCenterY),
          captionType:
            detectCaptionType(candidate.text.split("\n")[0] ?? candidate.text) ??
            (/\bphoto\b/i.test(candidate.text) ? "image" : null),
        };
      })
      .filter((candidate) => candidate.captionType || candidate.distance <= 140)
      .sort((left, right) => left.distance - right.distance)[0];

    const assetType = nearestCaption?.captionType ?? "illustration";
    const relativeOutputPath = item.outputPath
      ? path.join(params.embeddedAssetsPrefix, path.basename(item.outputPath)).replace(/\\/g, "/")
      : path.join(params.embeddedAssetsPrefix, `page-${String(params.page.pdfPageNumber).padStart(3, "0")}-embedded-${String(index + 1).padStart(2, "0")}.png`).replace(/\\/g, "/");

    return {
      localId: `${assetType}_${params.page.pdfPageNumber}_embedded_${index + 1}`,
      assetType,
      pageNumber: params.page.pdfPageNumber,
      captionText:
        nearestCaption?.text.split("\n").join(" ").trim() || `Page ${params.page.pdfPageNumber} ${assetType} ${index + 1}`,
      rawText: nearestCaption?.text,
      filePath: relativeOutputPath,
      nearbyContentLocalIds: params.nearbyContentLocalIds,
      metadata: {
        chapterTitle: params.chapter.title,
        chapterNumber: params.chapter.chapterNumber,
        extraction: "embedded_image",
        bbox: item.bbox,
        width: item.width,
        height: item.height,
        xref: item.xref,
      },
    } satisfies DetectedAsset;
  });
}

export async function extractPdfPagesFromFile(
  pdfPath: string,
  embedding: TextbookPipelineEmbeddingAdapter,
  medium: Medium = "en",
): Promise<ExtractedPdfPage[]> {
  const tempJsonPath = path.join(os.tmpdir(), `right-answer-pages-${randomUUID()}.json`);
  const tempScriptPath = path.join(os.tmpdir(), `right-answer-pages-${randomUUID()}.py`);
  const ocrWorkerCount = getOcrWorkerCount(os.cpus()?.length ?? 4);
  try {
    await writeFile(
      tempScriptPath,
      [
        "import json, fitz, os, re, sys, tempfile, threading, concurrent.futures",
        "try:",
        "    from rapidocr_onnxruntime import RapidOCR",
        "except Exception:",
        "    RapidOCR = None",
        "rapidocr_local = threading.local()",
        "def sanitize_text(value):",
        "    return re.sub(r'[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F\\x7F]', ' ', value or '')",
        "def looks_suspicious(raw_value, cleaned_value, image_count):",
        "    if not raw_value and not cleaned_value:",
        "        return image_count > 0",
        "    control_count = sum(1 for char in raw_value if ord(char) < 32 and char not in '\\n\\r\\t')",
        "    digit_count = sum(1 for char in cleaned_value if char.isdigit())",
        "    alpha_count = sum(1 for char in cleaned_value if char.isalpha())",
        "    text_length = max(1, len(cleaned_value))",
        "    raw_length = max(1, len(raw_value))",
        "    digit_ratio = digit_count / text_length",
        "    alpha_ratio = alpha_count / text_length",
        "    non_space_count = sum(1 for char in cleaned_value if not char.isspace())",
        "    whitespace_ratio = 1 - (non_space_count / text_length)",
        "    repeated_digits = '1234567890' in cleaned_value or '0123456789' in cleaned_value",
        "    return (",
        "        control_count >= max(20, int(raw_length * 0.08))",
        "        or (non_space_count < 24 and raw_length >= 120)",
        "        or (whitespace_ratio >= 0.72 and raw_length >= 120)",
        "        or (digit_ratio >= 0.7 and alpha_ratio <= 0.12 and text_length >= 200)",
        "        or (repeated_digits and alpha_ratio <= 0.2 and text_length >= 200)",
        "        or (alpha_count < 8 and image_count > 0 and text_length < 120)",
        "    )",
        "def get_ocr_engine():",
        "    engine = getattr(rapidocr_local, 'engine', None)",
        "    if engine is False:",
        "        return None",
        "    if engine is None:",
        "        if RapidOCR is None:",
        "            rapidocr_local.engine = False",
        "            return None",
        "        try:",
        "            rapidocr_local.engine = RapidOCR()",
        "        except Exception:",
        "            rapidocr_local.engine = False",
        "            return None",
        "    return rapidocr_local.engine",
        "def ocr_page(pdf_path, page_index):",
        "    engine = get_ocr_engine()",
        "    if engine is None:",
        "        return page_index, None, None",
        "    doc = fitz.open(pdf_path)",
        "    page = doc.load_page(page_index)",
        "    tmp_path = os.path.join(tempfile.gettempdir(), f'right-answer-ocr-{os.getpid()}-{threading.get_ident()}-{page_index + 1}.png')",
        "    page.get_pixmap(matrix=fitz.Matrix(1.5, 1.5), alpha=False).save(tmp_path)",
        "    try:",
        "        result, _ = engine(tmp_path)",
        "    finally:",
        "        doc.close()",
        "        try:",
        "            os.remove(tmp_path)",
        "        except OSError:",
        "            pass",
        "    if not result:",
        "        return page_index, None, None",
        "    ocr_lines = []",
        "    ocr_blocks = []",
        "    for item in result:",
        "        points, text, _score = item",
        "        text = sanitize_text(str(text).strip())",
        "        if not text:",
        "            continue",
        "        xs = [point[0] for point in points]",
        "        ys = [point[1] for point in points]",
        "        ocr_lines.append(text)",
        "        ocr_blocks.append({",
        "            'text': text,",
        "            'bbox': [float(min(xs)), float(min(ys)), float(max(xs)), float(max(ys))],",
        "            'blockType': 0,",
        "        })",
        "    if not ocr_lines:",
        "        return page_index, None, None",
        "    return page_index, '\\n'.join(ocr_lines), ocr_blocks",
        "pdf_path = sys.argv[1]",
        "output_path = sys.argv[2]",
        "ocr_worker_count = max(1, int(sys.argv[3]))",
        "enable_suspicious_ocr = sys.argv[4] == '1'",
        "pdf = fitz.open(pdf_path)",
        "pages = []",
        "suspicious_pages = []",
        "for index in range(pdf.page_count):",
        "    page = pdf.load_page(index)",
        "    raw_text = page.get_text('text') or ''",
        "    text = sanitize_text(raw_text)",
        "    blocks = []",
        "    for block in page.get_text('blocks'):",
        "        x0, y0, x1, y1, block_text, block_no, block_type = block",
        "        if not str(block_text).strip():",
        "            continue",
        "        blocks.append({",
        "            'text': sanitize_text(block_text),",
        "            'bbox': [float(x0), float(y0), float(x1), float(y1)],",
        "            'blockType': int(block_type),",
        "        })",
        "    image_count = len(page.get_image_info(xrefs=True))",
        "    if enable_suspicious_ocr and looks_suspicious(raw_text, text, image_count):",
        "        suspicious_pages.append(index)",
        "    pages.append({'pageNumber': index + 1, 'text': text, 'blocks': blocks, 'imageCount': image_count, 'ocrUsed': False})",
        "pdf.close()",
        "if enable_suspicious_ocr and suspicious_pages and RapidOCR is not None:",
        "    max_workers = max(1, min(len(suspicious_pages), ocr_worker_count))",
        "    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:",
        "        future_map = [executor.submit(ocr_page, pdf_path, page_index) for page_index in suspicious_pages]",
        "        for future in concurrent.futures.as_completed(future_map):",
        "            page_index, ocr_text, ocr_blocks = future.result()",
        "            if ocr_text:",
        "                pages[page_index]['text'] = ocr_text",
        "                pages[page_index]['blocks'] = ocr_blocks",
        "                pages[page_index]['ocrUsed'] = True",
        "with open(output_path, 'w', encoding='utf-8') as fp:",
        "    json.dump({'pages': pages}, fp, ensure_ascii=False)",
      ].join("\n"),
      "utf8",
    );
    await execFileAsync(
      "python",
        [
          tempScriptPath,
          pdfPath,
          tempJsonPath,
          String(ocrWorkerCount),
          "1",
        ],
      {
        windowsHide: true,
        timeout: 1_200_000,
        maxBuffer: 8 * 1024 * 1024,
      },
    );
    const payload = JSON.parse(await readFile(tempJsonPath, "utf8")) as {
      pages: Array<{
        pageNumber: number;
        text: string;
        ocrUsed?: boolean;
        imageCount?: number;
        blocks?: Array<{
          text: string;
          bbox: [number, number, number, number];
          blockType: number;
        }>;
      }>;
    };

    if (payload.pages?.length) {
      return payload.pages.map((page) => {
        const repairedText = repairExtractedText(page.text ?? "");
        const normalizedText = embedding.normalizeText(repairedText);
        const lineCount = repairedText.split("\n").filter((line) => line.trim().length > 0).length;
        return {
          pdfPageNumber: page.pageNumber,
          rawText: repairedText,
          normalizedText,
          charCount: normalizedText.length,
          lineCount,
          ocrUsed: page.ocrUsed === true,
          likelyImagePage: normalizedText.length < 60,
          tocScore: computeTocScore(repairedText),
          textBlocks: (page.blocks ?? []).map((block) => ({
            text: repairExtractedText(block.text ?? ""),
            bbox: block.bbox,
            blockType: block.blockType,
          })),
          embeddedImageCount: page.imageCount ?? 0,
        };
      });
    }
  } catch {
    // Fall through to pdf-parse if PyMuPDF is unavailable.
  } finally {
    await rm(tempJsonPath, { force: true }).catch(() => undefined);
    await rm(tempScriptPath, { force: true }).catch(() => undefined);
  }

  const buffer = await readFile(pdfPath);
  const parsed = await pdf(buffer);
  const pageTexts = splitPdfTextByPage(parsed.text, parsed.numpages);

  return pageTexts.map((pageText, index) => {
    const repairedText = repairExtractedText(pageText);
    const normalizedText = embedding.normalizeText(repairedText);
    const lineCount = repairedText.split("\n").filter((line) => line.trim().length > 0).length;
    return {
      pdfPageNumber: index + 1,
      rawText: repairedText,
      normalizedText,
      charCount: normalizedText.length,
      lineCount,
      ocrUsed: false,
      likelyImagePage: normalizedText.length < 60,
      tocScore: computeTocScore(repairedText),
      textBlocks: repairedText
        .split(/\n{2,}/)
        .map((block) => block.trim())
        .filter(Boolean)
        .map((block, blockIndex) => ({
          text: block,
          bbox: [0, blockIndex * 24, 0, blockIndex * 24 + 24],
          blockType: 0,
        })),
      embeddedImageCount: 0,
    };
  });
}

export async function detectChapterIndex(params: {
  pdfPath: string;
  pages: ExtractedPdfPage[];
  outputDir: string;
  chromePath?: string;
  tocScanPages?: number;
  forceCodexToc?: boolean;
  indexPages?: number[];
  manualChapters?: ManualChapterInput[];
}) {
  const debugToc = Boolean(process.env.RIGHT_ANSWER_DEBUG_TOC);
  const codexTocDisabled =
    process.env.RIGHT_ANSWER_DISABLE_CODEX_TOC === "1" || process.env.RIGHT_ANSWER_ENABLE_CODEX_TOC !== "1";
  const lockedIndexPages = (params.indexPages ?? []).filter(
    (pageNumber) => pageNumber >= 1 && pageNumber <= params.pages.length,
  );
  const scanLimit = Math.max(4, params.tocScanPages ?? 12);
  const earlyPages = params.pages.slice(0, scanLimit);
  const contentsPages = earlyPages.filter((page) => isLikelyContentsPage(page));
  const lockedCandidates = lockedIndexPages
    .map((pageNumber) => params.pages[pageNumber - 1])
    .filter((page): page is ExtractedPdfPage => Boolean(page));
  const candidates =
    lockedCandidates.length > 0
      ? lockedCandidates
      : [...(contentsPages.length > 0 ? contentsPages : earlyPages)]
          .sort((left, right) => right.tocScore - left.tocScore)
          .slice(0, 4);
  const codexCandidates =
    lockedCandidates.length > 0
      ? lockedCandidates
      : [...new Map((contentsPages.length > 0 ? contentsPages : earlyPages).map((page) => [page.pdfPageNumber, page])).values()].slice(0, Math.min(scanLimit, 8));

  const parsedBlockEntries = sanitizeChapterEntries(candidates.flatMap((page) => parseChapterEntriesFromBlocks(page.textBlocks)));
  const parsedFallbackTextEntries = sanitizeChapterEntries(candidates.flatMap((page) => parseChapterEntriesFromText(page.rawText)));
  const parsedFallbackCandidateEntries = sanitizeChapterEntries(
    assignSequentialChapterNumbers(
      extractFallbackEntriesFromCandidatePages(candidates, params.pages).map((entry) => ({
        chapterNumber: entry.chapterNumber,
        title: entry.title,
        printedStartPage: entry.printedStartPage,
        pdfStartPage: entry.printedStartPage,
        confidence: entry.confidence,
        source: "text" as const,
        matchReason: entry.matchReason,
      })),
    ),
  );
  const preferBlockEntries =
    parsedBlockEntries.length >= 2 &&
    !shouldUseCodexFallback(parsedBlockEntries, params.pages.length) &&
    chapterEntryQuality(parsedBlockEntries) >= chapterEntryQuality(parsedFallbackTextEntries) &&
    chapterEntryQuality(parsedBlockEntries) >= chapterEntryQuality(parsedFallbackCandidateEntries);
  const parsedTextEntries = preferBlockEntries
    ? parsedBlockEntries
    : chapterEntryQuality(parsedFallbackCandidateEntries) > chapterEntryQuality(parsedFallbackTextEntries)
      ? parsedFallbackCandidateEntries
      : parsedFallbackTextEntries;
  if (debugToc) {
    console.log(
      JSON.stringify({
        stage: "toc_parse",
        lockedIndexPages,
        candidatePages: candidates.map((page) => page.pdfPageNumber),
        candidateBlocks: candidates.map((page) => ({
          pdfPageNumber: page.pdfPageNumber,
          blocks: page.textBlocks.map((block) => repairExtractedText(normalizeWhitespace(block.text)).trim()).filter(Boolean),
        })),
        parsedBlockEntries,
        parsedFallbackTextEntries,
        parsedFallbackCandidateEntries,
        chosenParsedEntries: parsedTextEntries,
      }),
    );
  }
  let chosenEntries =
    params.manualChapters && params.manualChapters.length > 0
      ? sanitizeChapterEntries(
          params.manualChapters.map((entry) => ({
            chapterNumber: entry.chapterNumber,
            title: entry.title,
            printedStartPage: entry.printedStartPage,
            pdfStartPage: entry.printedStartPage,
            confidence: 1,
            source: "manual" as const,
            matchReason: "manual_input",
          })),
        )
      : parsedTextEntries;
  let source: "text" | "codex" | "manual" = params.manualChapters && params.manualChapters.length > 0 ? "manual" : "text";
  let codexNotes: string[] = [];
  let codexAttempted = false;
  const parsedQuality = chapterEntryQuality(parsedTextEntries);

  if (
    !codexTocDisabled &&
    source !== "manual" &&
    (params.forceCodexToc || shouldUseCodexFallback(chosenEntries, params.pages.length)) &&
    codexCandidates.length > 0
  ) {
    if (debugToc) {
      console.log(
        JSON.stringify({
          stage: "toc_codex_attempt",
          reason: params.forceCodexToc ? "forced" : "fallback",
          codexCandidatePages: codexCandidates.map((page) => page.pdfPageNumber),
          chosenEntries,
        }),
      );
    }
    codexAttempted = true;
    try {
      const codexResult = await detectChaptersWithCodex({
        pdfPath: params.pdfPath,
        candidatePages: codexCandidates,
        outputDir: params.outputDir,
        chromePath: params.chromePath,
      });
      codexNotes = codexResult.notes;
      if (codexResult.entries.length >= 2 && chapterEntryQuality(codexResult.entries) >= parsedQuality) {
        chosenEntries = codexResult.entries;
        source = "codex";
      }
    } catch (error) {
      codexNotes = [error instanceof Error ? error.message : String(error)];
    }
  }

  let inferredPrintedPageOffset = 0;
  if (
    chosenEntries.length >= 2 &&
    chosenEntries.some((entry) => entry.printedStartPage > params.pages.length || entry.printedStartPage > scanLimit + 20)
  ) {
    const earliestTocCandidatePage =
      candidates.map((page) => page.pdfPageNumber).sort((left, right) => left - right)[0] ?? 1;
    const estimatedFirstChapterPage = Math.min(params.pages.length, Math.max(1, earliestTocCandidatePage + 2));
    inferredPrintedPageOffset = Math.max(0, chosenEntries[0]!.printedStartPage - estimatedFirstChapterPage);
  }

  let resolvedEntries = finalizeChapterRanges(
    resolveChapterStartPages(chosenEntries, params.pages, inferredPrintedPageOffset),
    params.pages.length,
  );
  if (debugToc) {
    console.log(
      JSON.stringify({
        stage: "toc_resolved_initial",
        source,
        inferredPrintedPageOffset,
        resolvedEntries,
      }),
    );
  }
  const hasBrokenResolvedRanges = resolvedEntries.some(
    (entry, index) =>
      (entry.pdfEndPage ?? entry.pdfStartPage) < entry.pdfStartPage ||
      (index > 0 && entry.pdfStartPage <= resolvedEntries[index - 1]!.pdfStartPage),
  );

  if (!codexTocDisabled && source === "text" && !codexAttempted && codexCandidates.length > 0 && hasBrokenResolvedRanges) {
    codexAttempted = true;
    try {
      const codexResult = await detectChaptersWithCodex({
        pdfPath: params.pdfPath,
        candidatePages: codexCandidates,
        outputDir: params.outputDir,
        chromePath: params.chromePath,
      });
      codexNotes = codexResult.notes;
      if (codexResult.entries.length >= 2) {
        source = "codex";
        chosenEntries = codexResult.entries;
        resolvedEntries = finalizeChapterRanges(
          resolveChapterStartPages(chosenEntries, params.pages, inferredPrintedPageOffset),
          params.pages.length,
        );
      }
    } catch (error) {
      codexNotes = [error instanceof Error ? error.message : String(error)];
    }
  }

  return {
    chapters: resolvedEntries,
    evidence: {
      source,
      lockedIndexPages,
      tocCandidatePages: candidates.map((page) => ({
        pdfPageNumber: page.pdfPageNumber,
        tocScore: page.tocScore,
        charCount: page.charCount,
        blockCount: page.textBlocks.length,
        contentsHint: containsContentsHint(page.rawText),
      })),
      parsedBlockEntries,
      parsedTextEntries,
      parsedTextQuality: parsedQuality,
      inferredPrintedPageOffset,
      codexAttempted,
      codexNotes: source === "codex" ? codexNotes : [],
    },
  };
}

function formatChapterEntries(entries: ChapterIndexEntry[]) {
  return entries
    .map(
      (entry) =>
        `  ${entry.chapterNumber}. ${entry.title} | printed ${entry.printedStartPage} | pdf ${entry.pdfStartPage}-${entry.pdfEndPage ?? "?"} | ${entry.source}`,
    )
    .join("\n");
}

async function promptForIndexPages(current: number[]) {
  const rl = createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  try {
    const answer = await rl.question(
      `Enter index page numbers separated by commas${current.length ? ` [current: ${current.join(", ")}]` : ""}: `,
    );
    return parseNumberList([answer]);
  } finally {
    rl.close();
  }
}

async function promptForManualChapters(current: ChapterIndexEntry[]) {
  const rl = createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  try {
    console.log("Enter chapter rows as chapterNumber|title|printedStartPage.");
    console.log("Use semicolons to enter multiple rows on one line.");
    console.log(
      current.length
        ? `Current rows:\n${current
            .map((entry) => `${entry.chapterNumber}|${entry.title}|${entry.printedStartPage}`)
            .join("; ")}`
        : "No current chapter rows.",
    );
    const answer = await rl.question("Chapter rows: ");
    return sanitizeManualChapterInputs(parseManualChapterStrings([answer]));
  } finally {
    rl.close();
  }
}

export async function reviewChapterDetection(params: {
  pdfPath: string;
  pages: ExtractedPdfPage[];
  outputDir: string;
  chromePath?: string;
  tocScanPages?: number;
  forceCodexToc?: boolean;
  initialIndexPages?: number[];
  initialManualChapters?: ManualChapterInput[];
}) {
  let indexPages = [...(params.initialIndexPages ?? [])];
  let manualChapters = sanitizeManualChapterInputs(params.initialManualChapters ?? []);

  while (true) {
    const detection = await detectChapterIndex({
      pdfPath: params.pdfPath,
      pages: params.pages,
      outputDir: params.outputDir,
      chromePath: params.chromePath,
      tocScanPages: params.tocScanPages,
      forceCodexToc: params.forceCodexToc,
      indexPages,
      manualChapters,
    });

    console.log("\nDetected chapter index:");
    console.log(formatChapterEntries(detection.chapters) || "  No chapters detected.");
    console.log(
      `Index pages used: ${
        detection.evidence.lockedIndexPages?.length
          ? detection.evidence.lockedIndexPages.join(", ")
          : detection.evidence.tocCandidatePages.map((page) => page.pdfPageNumber).join(", ")
      }`,
    );

    const rl = createInterface({
      input: process.stdin,
      output: process.stdout,
    });

    try {
      const answer = (
        await rl.question(
          "Accept detection? [Y]es / [I]ndex pages edit / [C]hapters edit / [B]oth edit / [N] cancel: ",
        )
      )
        .trim()
        .toLowerCase();

      if (answer === "" || answer === "y" || answer === "yes") {
        return detection;
      }
      if (answer === "n" || answer === "no") {
        throw new Error("Textbook ingestion cancelled during chapter confirmation.");
      }
      if (answer === "i" || answer === "index") {
        indexPages = await promptForIndexPages(indexPages);
        manualChapters = [];
        continue;
      }
      if (answer === "c" || answer === "chapters") {
        manualChapters = await promptForManualChapters(detection.chapters);
        continue;
      }
      if (answer === "b" || answer === "both") {
        indexPages = await promptForIndexPages(indexPages);
        manualChapters = await promptForManualChapters(detection.chapters);
        continue;
      }
    } finally {
      rl.close();
    }
  }
}

async function resolveChapterDetection(params: {
  pdfPath: string;
  pages: ExtractedPdfPage[];
  outputDir: string;
  chromePath?: string;
  tocScanPages?: number;
  forceCodexToc?: boolean;
  interactiveConfirm?: boolean;
  indexPages?: number[];
  manualChapters?: ManualChapterInput[];
}) {
  if (params.interactiveConfirm) {
    return reviewChapterDetection({
      pdfPath: params.pdfPath,
      pages: params.pages,
      outputDir: params.outputDir,
      chromePath: params.chromePath,
      tocScanPages: params.tocScanPages,
      forceCodexToc: params.forceCodexToc,
      initialIndexPages: params.indexPages,
      initialManualChapters: params.manualChapters,
    });
  }

  return detectChapterIndex({
    pdfPath: params.pdfPath,
    pages: params.pages,
    outputDir: params.outputDir,
    chromePath: params.chromePath,
    tocScanPages: params.tocScanPages,
    forceCodexToc: params.forceCodexToc,
    indexPages: params.indexPages,
    manualChapters: params.manualChapters,
  });
}

export async function buildProcessedArtifacts(params: {
  pdfPath: string;
  pages: ExtractedPdfPage[];
  chapters: ChapterIndexEntry[];
  subjectCode: string;
  medium: Medium;
  versionLabel: string;
  chromePath?: string;
  keepDebugArtifacts?: boolean;
  embedding: TextbookPipelineEmbeddingAdapter;
}) {
  const storage = new LocalStorageAdapter(path.resolve(process.cwd(), STORAGE_ROOT));
  const pageArtifacts: Array<Record<string, unknown>> = [];
  const contentUnits: StructuredContentUnit[] = [];
  const assets: DetectedAsset[] = [];
  const questions: StructuredQuestionRecord[] = [];
  const exercises: StructuredExerciseRecord[] = [];

  const pagesPrefix = buildTextbookStorageKey({
    syllabus: "sslc",
    subjectSlug: params.subjectCode,
    medium: params.medium,
    versionLabel: params.versionLabel,
    kind: "processed",
    fileName: "pages",
  });
  const assetsPrefix = buildTextbookStorageKey({
    syllabus: "sslc",
    subjectSlug: params.subjectCode,
    medium: params.medium,
    versionLabel: params.versionLabel,
    kind: "processed",
    fileName: "assets",
  });
  const tablesPrefix = buildTextbookStorageKey({
    syllabus: "sslc",
    subjectSlug: params.subjectCode,
    medium: params.medium,
    versionLabel: params.versionLabel,
    kind: "processed",
    fileName: "tables",
  });
  const graphsPrefix = buildTextbookStorageKey({
    syllabus: "sslc",
    subjectSlug: params.subjectCode,
    medium: params.medium,
    versionLabel: params.versionLabel,
    kind: "processed",
    fileName: "graphs",
  });
  const diagramsPrefix = buildTextbookStorageKey({
    syllabus: "sslc",
    subjectSlug: params.subjectCode,
    medium: params.medium,
    versionLabel: params.versionLabel,
    kind: "processed",
    fileName: "diagrams",
  });
  const embeddedAssetsPrefix = path.join(assetsPrefix, "embedded");
  const chapterWorkerCount = getChapterWorkerCount(params.chapters.length);
  const pagesByChapter = new Map<number, ExtractedPdfPage[]>();
  for (const page of params.pages) {
    const chapter = mapPageToChapter(page.pdfPageNumber, params.chapters);
    if (!chapter) continue;
    const existing = pagesByChapter.get(chapter.chapterNumber) ?? [];
    existing.push(page);
    pagesByChapter.set(chapter.chapterNumber, existing);
  }

  const chapterResults = await mapWithConcurrency(params.chapters, chapterWorkerCount, async (chapter) => {
    const chapterPages = (pagesByChapter.get(chapter.chapterNumber) ?? []).sort(
      (left, right) => left.pdfPageNumber - right.pdfPageNumber,
    );
    const chapterPageArtifacts: Array<Record<string, unknown>> = [];
    const chapterContentUnits: StructuredContentUnit[] = [];
    const chapterAssets: DetectedAsset[] = [];
    const chapterQuestions: StructuredQuestionRecord[] = [];
    const chapterExercises = new Map<string, StructuredExerciseRecord>();

    for (const page of chapterPages) {
      const blocks = splitPageIntoBlocks(page, chapter);
      const pageImagePath = path.join(assetsPrefix, `page-${String(page.pdfPageNumber).padStart(3, "0")}.png`);

      const localContentIdsForPage: string[] = [];
      let currentParentLocalId: string | undefined;
      let currentQuestionLocalId: string | undefined;
      let currentExerciseLocalId = `exercise_${chapter.chapterNumber}`;

      for (let blockIndex = 0; blockIndex < blocks.length; blockIndex += 1) {
        const block = blocks[blockIndex];
        const contentType = detectContentType(block, chapter.chapterNumber, chapter.title);
        const normalizedText = params.embedding.normalizeText(block);
        const localId = `p${page.pdfPageNumber}_b${blockIndex + 1}_${contentType}`;
        const textLine = block.split("\n")[0]?.trim() ?? block.slice(0, 80);

        if (
          contentType === "section_heading" ||
          contentType === "subsection_heading" ||
          contentType === "chapter_heading"
        ) {
          currentParentLocalId = localId;
        }
        if (contentType === "exercise") {
          currentExerciseLocalId = `exercise_${chapter.chapterNumber}_${slugify(textLine) || page.pdfPageNumber}`;
          const existingExercise = chapterExercises.get(currentExerciseLocalId);
          if (existingExercise) {
            existingExercise.pageEnd = page.pdfPageNumber;
          } else {
            chapterExercises.set(currentExerciseLocalId, {
              localId: currentExerciseLocalId,
              chapterNumber: chapter.chapterNumber,
              pageStart: page.pdfPageNumber,
              pageEnd: page.pdfPageNumber,
              title: textLine,
              exerciseType: "exercise_section",
            });
          }
        }
        if (contentType === "question") {
          currentQuestionLocalId = localId;
          const exercise = chapterExercises.get(currentExerciseLocalId) ?? {
            localId: currentExerciseLocalId,
            chapterNumber: chapter.chapterNumber,
            pageStart: page.pdfPageNumber,
            pageEnd: page.pdfPageNumber,
            title: `Chapter ${chapter.chapterNumber} Exercises`,
            exerciseType: "detected_questions",
          };
          exercise.pageEnd = page.pdfPageNumber;
          chapterExercises.set(currentExerciseLocalId, exercise);
          chapterQuestions.push({
            localId: `question_${localId}`,
            exerciseLocalId: exercise.localId,
            chapterNumber: chapter.chapterNumber,
            pageNumber: page.pdfPageNumber,
            contentUnitLocalId: localId,
            title: exercise.title,
            questionText: block,
            questionNumber: textLine.match(/^\d+/)?.[0],
          });
        }
        if (contentType === "sub_question" && currentQuestionLocalId) {
          const exercise = chapterExercises.get(currentExerciseLocalId) ?? {
            localId: currentExerciseLocalId,
            chapterNumber: chapter.chapterNumber,
            pageStart: page.pdfPageNumber,
            pageEnd: page.pdfPageNumber,
            title: `Chapter ${chapter.chapterNumber} Exercises`,
            exerciseType: "detected_questions",
          };
          exercise.pageEnd = page.pdfPageNumber;
          chapterExercises.set(currentExerciseLocalId, exercise);
          chapterQuestions.push({
            localId: `question_${localId}`,
            exerciseLocalId: exercise.localId,
            parentLocalId: `question_${currentQuestionLocalId}`,
            chapterNumber: chapter.chapterNumber,
            pageNumber: page.pdfPageNumber,
            contentUnitLocalId: localId,
            title: exercise.title,
            questionText: block,
            questionNumber: textLine.match(/^\(?([a-z]|[ivx]+)\)?/i)?.[0],
          });
        }

        const record: StructuredContentUnit = {
          localId,
          pageNumber: page.pdfPageNumber,
          chapterNumber: chapter.chapterNumber,
          contentType,
          text: block,
          normalizedText,
          parentLocalId:
            contentType === "paragraph" || contentType === "definition" || contentType === "formula"
              ? currentParentLocalId
              : undefined,
          keywords: keywordSlice(normalizedText),
          metadata: {
            chapterTitle: chapter.title,
            blockIndex,
            pageNumber: page.pdfPageNumber,
          },
        };
        chapterContentUnits.push(record);
        localContentIdsForPage.push(localId);
      }

      const textDetectedAssets = detectPageAssets({
        page,
        blocks,
        chapter,
        pageImagePath,
        nearbyContentLocalIds: localContentIdsForPage.slice(-3),
      });
      const embeddedDetectedAssets = await extractEmbeddedAssetsForPage({
        pdfPath: params.pdfPath,
        page,
        chapter,
        embeddedAssetsDir: path.resolve(process.cwd(), STORAGE_ROOT, embeddedAssetsPrefix),
        embeddedAssetsPrefix,
        nearbyContentLocalIds: localContentIdsForPage.slice(-5),
      }).catch(() => []);
      const detectedAssets = [...textDetectedAssets, ...embeddedDetectedAssets];
      chapterAssets.push(...detectedAssets);

      if (textDetectedAssets.length > 0) {
        try {
          await renderPdfPageImage({
            pdfPath: params.pdfPath,
            pageNumber: page.pdfPageNumber,
            outputPath: path.resolve(process.cwd(), STORAGE_ROOT, pageImagePath),
            chromePath: params.chromePath,
          });
        } catch {
          // Page images are best-effort for local inspection and fallback review.
        }
      }

      const pageArtifact = {
        pageNumber: page.pdfPageNumber,
        chapterNumber: chapter.chapterNumber,
        chapterTitle: chapter.title,
        rawText: page.rawText,
        normalizedText: page.normalizedText,
        likelyImagePage: page.likelyImagePage,
        embeddedImageCount: page.embeddedImageCount,
        contentUnits: localContentIdsForPage,
        assets: detectedAssets.map((asset) => asset.localId),
      };
      chapterPageArtifacts.push(pageArtifact);

      await storage.put(
        path.join(pagesPrefix, `${String(page.pdfPageNumber).padStart(3, "0")}.json`),
        JSON.stringify(pageArtifact, null, 2),
      );
    }

    const chapterSummaryArtifact = buildChapterSummaryArtifact({
      chapter,
      pageArtifacts: chapterPageArtifacts,
      contentUnits: chapterContentUnits,
      assets: chapterAssets,
      questions: chapterQuestions,
    });

    await storage.put(
      buildTextbookStorageKey({
        syllabus: "sslc",
        subjectSlug: params.subjectCode,
        medium: params.medium,
        versionLabel: params.versionLabel,
        kind: "processed",
        fileName: `chapters/chapter-${String(chapter.chapterNumber).padStart(2, "0")}.json`,
      }),
      JSON.stringify(chapterSummaryArtifact, null, 2),
    );

    console.log(
      `[chapter] ${params.subjectCode}/${params.medium}/${params.versionLabel} chapter ${String(chapter.chapterNumber).padStart(2, "0")} complete`,
    );

    return {
      pageArtifacts: chapterPageArtifacts,
      contentUnits: chapterContentUnits,
      assets: chapterAssets,
      exercises: [...chapterExercises.values()].sort((left, right) => left.pageStart - right.pageStart),
      questions: chapterQuestions,
    };
  });

  for (const result of chapterResults) {
    pageArtifacts.push(...result.pageArtifacts);
    contentUnits.push(...result.contentUnits);
    assets.push(...result.assets);
    exercises.push(...result.exercises);
    questions.push(...result.questions);
  }

  pageArtifacts.sort((left, right) => Number(left.pageNumber ?? 0) - Number(right.pageNumber ?? 0));
  contentUnits.sort((left, right) => left.pageNumber - right.pageNumber);
  assets.sort((left, right) => left.pageNumber - right.pageNumber);
  exercises.sort((left, right) => left.pageStart - right.pageStart);
  questions.sort((left, right) => left.pageNumber - right.pageNumber);

  for (const asset of assets) {
    const targetFolder =
      asset.assetType === "table"
        ? tablesPrefix
        : asset.assetType === "graph"
          ? graphsPrefix
          : asset.assetType === "diagram"
            ? diagramsPrefix
            : assetsPrefix;
    const artifact = {
      ...asset,
      tableParse: asset.assetType === "table" && asset.rawText ? parseTableRows(asset.rawText) : undefined,
    };

    await storage.put(path.join(targetFolder, `${slugify(asset.localId)}.json`), JSON.stringify(artifact, null, 2));
    await storage.put(path.join(assetsPrefix, `${slugify(asset.localId)}.json`), JSON.stringify(artifact, null, 2));
  }

  return {
    pages: params.pages,
    chapters: params.chapters,
    contentUnits,
    assets,
    exercises,
    questions,
    tocEvidence: {},
    pageArtifacts,
  } satisfies ProcessedTextbookArtifacts;
}

async function persistRawPdf(params: {
  options: TextbookPipelineOptions;
  checksum: string;
  buffer: Buffer;
  storage: StorageAdapter;
}) {
  const rawPdfPath = buildTextbookStorageKey({
    syllabus: "sslc",
    subjectSlug: params.options.subjectCode,
    medium: params.options.medium,
    versionLabel: params.options.versionLabel,
    kind: "raw",
    fileName: "source.pdf",
  });
  const rawMetaPath = buildTextbookStorageKey({
    syllabus: "sslc",
    subjectSlug: params.options.subjectCode,
    medium: params.options.medium,
    versionLabel: params.options.versionLabel,
    kind: "raw",
    fileName: "source.meta.json",
  });

  await params.storage.put(rawPdfPath, params.buffer);
  await params.storage.put(
    rawMetaPath,
    JSON.stringify(
      {
        checksumSha256: params.checksum,
        sourceUrl: params.options.sourceUrl ?? null,
        sourceType: params.options.sourceType ?? "manual_local_script",
        sourceDomain: params.options.sourceDomain ?? null,
        partLabel: params.options.partLabel ?? null,
        downloadedAt: new Date().toISOString(),
        localScript: true,
      },
      null,
      2,
    ),
  );

  return { rawPdfPath, rawMetaPath };
}

async function upsertTextbookVersion(params: {
  prisma: PrismaClient;
  options: TextbookPipelineOptions;
  checksum: string;
  rawPdfPath: string;
}) {
  const subject =
    (await params.prisma.subject.findFirst({
      where: {
        code: params.options.subjectCode,
        classLevel: params.options.classLevel ?? 10,
        syllabus: params.options.syllabus ?? "Kerala SSLC",
      },
    })) ??
    (await params.prisma.subject.create({
      data: {
        code: params.options.subjectCode,
        name: params.options.subjectName ?? titleCaseFromCode(params.options.subjectCode),
        classLevel: params.options.classLevel ?? 10,
        syllabus: params.options.syllabus ?? "Kerala SSLC",
        active: true,
      },
    }));

  const textbook =
    (await params.prisma.textbook.findFirst({
      where: {
        subjectId: subject.id,
        medium: params.options.medium,
        classLevel: params.options.classLevel ?? 10,
        syllabus: params.options.syllabus ?? "Kerala SSLC",
        partLabel: params.options.partLabel,
      },
    })) ??
    (await params.prisma.textbook.create({
      data: {
        subjectId: subject.id,
        title:
          params.options.title ??
          ([subject.name, params.options.partLabel].filter(Boolean).join(" ") || `${subject.name} Textbook`),
        medium: params.options.medium,
        classLevel: params.options.classLevel ?? 10,
        syllabus: params.options.syllabus ?? "Kerala SSLC",
        publisher: params.options.publisher ?? "Kerala SCERT",
        partLabel: params.options.partLabel,
      },
    }));

  if (
    (params.options.title && params.options.title !== textbook.title) ||
    (params.options.publisher && params.options.publisher !== textbook.publisher) ||
    params.options.partLabel !== textbook.partLabel
  ) {
    await params.prisma.textbook.update({
      where: { id: textbook.id },
      data: {
        title: params.options.title ?? textbook.title,
        publisher: params.options.publisher ?? textbook.publisher,
        partLabel: params.options.partLabel,
      },
    });
  }

  const existingByChecksum = await params.prisma.textbookVersion.findFirst({
    where: {
      textbookId: textbook.id,
      checksumSha256: params.checksum,
    },
  });
  const existingByVersion =
    existingByChecksum ??
    (params.options.existingVersionId
      ? await params.prisma.textbookVersion.findUnique({
          where: { id: params.options.existingVersionId },
        })
      : await params.prisma.textbookVersion.findFirst({
          where: {
            textbookId: textbook.id,
            versionLabel: params.options.versionLabel,
          },
        }));

  const version = existingByVersion
      ? await params.prisma.textbookVersion.update({
        where: { id: existingByVersion.id },
        data: {
          textbookId: textbook.id,
          versionLabel: params.options.versionLabel,
          academicYear: params.options.academicYear,
          sourceUrl: params.options.sourceUrl,
          sourceType: params.options.sourceType ?? "manual_local_script",
          sourceDomain: params.options.sourceDomain,
          checksumSha256: params.checksum,
          storagePath: params.rawPdfPath,
          status: "processing",
          downloadedAt: new Date(),
          metadata: {
            ...(existingByVersion.metadata as Record<string, unknown> | undefined),
            title: params.options.title ?? textbook.title,
            partLabel: params.options.partLabel ?? null,
          },
        },
      })
    : await params.prisma.textbookVersion.create({
        data: {
          textbookId: textbook.id,
          versionLabel: params.options.versionLabel,
          academicYear: params.options.academicYear,
          sourceUrl: params.options.sourceUrl,
          sourceType: params.options.sourceType ?? "manual_local_script",
          sourceDomain: params.options.sourceDomain,
          checksumSha256: params.checksum,
          storagePath: params.rawPdfPath,
          status: "processing",
          downloadedAt: new Date(),
          metadata: {
            title: params.options.title ?? textbook.title,
            partLabel: params.options.partLabel ?? null,
          },
        },
      });

  return {
    subject,
    textbook,
    version,
  };
}

async function updateIngestionJob(
  prisma: PrismaClient,
  jobId: string,
  stage: IngestionStage,
  status: JobStatus,
  metrics?: Prisma.InputJsonValue,
  errorMessage?: string,
) {
  await prisma.ingestionJob.update({
    where: { id: jobId },
    data: {
      stage,
      status,
      errorMessage,
      metrics: metrics ?? undefined,
    },
  });
}

async function canUsePgVector(prisma: PrismaClient) {
  if (vectorColumnSupported !== null) {
    return vectorColumnSupported;
  }

  try {
    const result = (await prisma.$queryRawUnsafe(`SELECT to_regtype('vector')::text AS vector_type`)) as Array<{
      vector_type: string | null;
    }>;
    vectorColumnSupported = Boolean(result[0]?.vector_type);
  } catch {
    vectorColumnSupported = false;
  }

  return vectorColumnSupported;
}

export async function persistProcessedTextbook(params: {
  prisma: PrismaClient;
  storage: StorageAdapter;
  embedding: TextbookPipelineEmbeddingAdapter;
  options: TextbookPipelineOptions;
  checksum: string;
  rawPdfPath: string;
  artifacts: ProcessedTextbookArtifacts;
  tocEvidence: Record<string, unknown>;
}) {
  const { subject, textbook, version } = await upsertTextbookVersion({
    prisma: params.prisma,
    options: params.options,
    checksum: params.checksum,
    rawPdfPath: params.rawPdfPath,
  });

  const job = await params.prisma.ingestionJob.create({
    data: {
      textbookId: textbook.id,
      textbookVersionId: version.id,
      status: "running",
      stage: "parsed",
      metrics: {
        source: "local_textbook_pipeline",
      },
    },
  });

  try {
    await params.prisma.page.deleteMany({ where: { textbookVersionId: version.id } });
    await params.prisma.chapter.deleteMany({ where: { textbookVersionId: version.id } });

    await updateIngestionJob(params.prisma, job.id, "structured", "running", {
      pageCount: params.artifacts.pages.length,
      chapterCount: params.artifacts.chapters.length,
    });

    const chapterIdByNumber = new Map<number, string>();
    for (const chapter of params.artifacts.chapters) {
      const created = await params.prisma.chapter.create({
        data: {
          textbookVersionId: version.id,
          chapterNumber: chapter.chapterNumber,
          title: chapter.title,
          startPage: chapter.pdfStartPage,
          endPage: chapter.pdfEndPage,
        },
      });
      chapterIdByNumber.set(chapter.chapterNumber, created.id);
    }

    const pageIdByNumber = new Map<number, string>();
    for (const page of params.artifacts.pages) {
      const chapter = mapPageToChapter(page.pdfPageNumber, params.artifacts.chapters);
      if (!chapter) continue;

      const pageStoragePath = buildTextbookStorageKey({
        syllabus: "sslc",
        subjectSlug: params.options.subjectCode,
        medium: params.options.medium,
        versionLabel: params.options.versionLabel,
        kind: "processed",
        fileName: `pages/${String(page.pdfPageNumber).padStart(3, "0")}.json`,
      });

      const created = await params.prisma.page.create({
        data: {
          textbookVersionId: version.id,
          chapterId: chapterIdByNumber.get(chapter.chapterNumber),
          pageNumber: page.pdfPageNumber,
          rawText: page.rawText,
          normalizedText: page.normalizedText,
          ocrUsed: page.ocrUsed,
          parseConfidence: page.ocrUsed ? 0.78 : page.likelyImagePage ? 0.55 : 0.92,
          storagePath: pageStoragePath,
          metadata: {
            tocScore: page.tocScore,
            likelyImagePage: page.likelyImagePage,
            ocrUsed: page.ocrUsed,
          },
        },
      });
      pageIdByNumber.set(page.pdfPageNumber, created.id);
    }

    const contentUnitIdByLocalId = new Map<string, string>();
    const contentUnitsForEmbedding: Array<{
      localId: string;
      contentUnitId: string;
      pageNumber: number;
      chapterNumber: number;
      normalizedText: string;
      contentHash: string;
    }> = [];
    for (const unit of params.artifacts.contentUnits) {
      const chapterId = chapterIdByNumber.get(unit.chapterNumber);
      const pageId = pageIdByNumber.get(unit.pageNumber);
      if (!chapterId || !pageId) continue;

      const created = await params.prisma.contentUnit.create({
        data: {
          pageId,
          chapterId,
          parentContentUnitId: unit.parentLocalId ? contentUnitIdByLocalId.get(unit.parentLocalId) : undefined,
          contentType: unit.contentType,
          text: unit.text,
          normalizedText: unit.normalizedText,
          language: params.options.language ?? (params.options.medium === "ml" ? "ml" : "en"),
          keywords: unit.keywords,
          contentHash: createHash("sha256")
            .update(`${version.id}:${unit.pageNumber}:${unit.chapterNumber}:${unit.localId}:${unit.text}`)
            .digest("hex"),
          metadata: unit.metadata as Prisma.InputJsonValue,
        },
      });
      contentUnitIdByLocalId.set(unit.localId, created.id);
      contentUnitsForEmbedding.push({
        localId: unit.localId,
        contentUnitId: created.id,
        pageNumber: unit.pageNumber,
        chapterNumber: unit.chapterNumber,
        normalizedText: unit.normalizedText,
        contentHash: created.contentHash,
      });
    }

    for (const batch of chunkArray(contentUnitsForEmbedding, 24)) {
      const embeddingValuesBatch = await params.embedding.embedTexts(
        batch.map((unit) => unit.normalizedText),
        "document",
      );

      for (const [index, unit] of batch.entries()) {
        const embeddingValues = embeddingValuesBatch[index] ?? [];
        const embedding = await params.prisma.embedding.create({
          data: {
            contentUnitId: unit.contentUnitId,
            embeddingModel: DEFAULT_EMBEDDING_MODEL,
            embeddingVersion: "v1",
            embeddingValues,
            contentHash: unit.contentHash,
          },
        });

        if (await canUsePgVector(params.prisma)) {
          await params.prisma.$executeRawUnsafe(
            `UPDATE "Embedding" SET "embedding_vector" = $1::vector WHERE id = $2::uuid`,
            params.embedding.toVectorLiteral(embeddingValues),
            embedding.id,
          );
        }

        await params.storage.put(
          buildTextbookStorageKey({
            syllabus: "sslc",
            subjectSlug: params.options.subjectCode,
            medium: params.options.medium,
            versionLabel: params.options.versionLabel,
            kind: "processed",
            fileName: `embeddings/${slugify(unit.localId)}.json`,
          }),
          JSON.stringify(
            {
              localId: unit.localId,
              contentUnitId: unit.contentUnitId,
              pageNumber: unit.pageNumber,
              chapterNumber: unit.chapterNumber,
              embeddingModel: DEFAULT_EMBEDDING_MODEL,
              embeddingVersion: "v1",
              contentHash: unit.contentHash,
              embeddingValues,
            },
            null,
            2,
          ),
        );
      }
    }

    const exerciseIdByLocalId = new Map<string, string>();
    for (const exercise of params.artifacts.exercises) {
      const chapterId = chapterIdByNumber.get(exercise.chapterNumber);
      if (!chapterId) continue;

      const created = await params.prisma.exercise.create({
        data: {
          chapterId,
          title: exercise.title,
          pageStart: exercise.pageStart,
          pageEnd: exercise.pageEnd,
          exerciseType: exercise.exerciseType,
        },
      });
      exerciseIdByLocalId.set(exercise.localId, created.id);
    }

    const questionIdByLocalId = new Map<string, string>();
    for (const question of params.artifacts.questions) {
      const exercise = exerciseIdByLocalId.get(question.exerciseLocalId);
      if (!exercise) continue;

      const created = await params.prisma.question.create({
        data: {
          exerciseId: exercise,
          parentQuestionId: question.parentLocalId ? questionIdByLocalId.get(question.parentLocalId) : undefined,
          contentUnitId: question.contentUnitLocalId ? contentUnitIdByLocalId.get(question.contentUnitLocalId) : undefined,
          questionNumber: question.questionNumber,
          questionText: question.questionText,
          answerHint: question.answerHint,
        },
      });
      questionIdByLocalId.set(question.localId, created.id);
    }

    for (const asset of params.artifacts.assets) {
      const pageId = pageIdByNumber.get(asset.pageNumber);
      if (!pageId) continue;

      const created = await params.prisma.textbookAsset.create({
        data: {
          contentUnitId: asset.nearbyContentLocalIds[0]
            ? contentUnitIdByLocalId.get(asset.nearbyContentLocalIds[0])
            : undefined,
          pageId,
          assetType: asset.assetType,
          filePath: asset.filePath,
          captionText: asset.captionText || null,
          ocrText: asset.rawText ?? null,
          nearbyContentUnitIds: asset.nearbyContentLocalIds
            .map((localId) => contentUnitIdByLocalId.get(localId))
            .filter((value): value is string => Boolean(value)),
          metadata: asset.metadata as Prisma.InputJsonValue,
        },
      });

      if (asset.assetType === "table") {
        const tableData = asset.rawText ? parseTableRows(asset.rawText) : { headers: [], rows: [] };
        await params.prisma.tableAsset.create({
          data: {
            assetId: created.id,
            contentUnitId: created.contentUnitId ?? undefined,
            rawTableText: asset.rawText,
            columnHeaders: tableData.headers,
            structuredRows: tableData.rows,
            generatedExplanation: asset.captionText || null,
          },
        });
      } else if (asset.assetType === "graph") {
        await params.prisma.graphAsset.create({
          data: {
            assetId: created.id,
            graphType: "unknown",
            captionText: asset.captionText,
            generatedExplanation: asset.captionText || null,
            possibleQuestions: [],
          },
        });
      } else if (asset.assetType === "diagram") {
        await params.prisma.diagramAsset.create({
          data: {
            assetId: created.id,
            captionText: asset.captionText,
            labelMap: [],
            generatedDescription: asset.captionText || null,
            possibleQuestions: [],
          },
        });
      }
    }

    await params.storage.put(
      buildTextbookStorageKey({
        syllabus: "sslc",
        subjectSlug: params.options.subjectCode,
        medium: params.options.medium,
        versionLabel: params.options.versionLabel,
        kind: "processed",
        fileName: "chapter-index.json",
      }),
      JSON.stringify(
        {
          chapters: params.artifacts.chapters,
          evidence: params.tocEvidence,
        },
        null,
        2,
      ),
    );
    await params.storage.put(
      buildTextbookStorageKey({
        syllabus: "sslc",
        subjectSlug: params.options.subjectCode,
        medium: params.options.medium,
        versionLabel: params.options.versionLabel,
        kind: "processed",
        fileName: "textbook.json",
      }),
      JSON.stringify(
        {
          textbookVersionId: version.id,
          subjectCode: subject.code,
          title: params.options.title ?? textbook.title,
          partLabel: params.options.partLabel ?? null,
          chapters: params.artifacts.chapters,
          pageCount: params.artifacts.pages.length,
          contentUnitCount: params.artifacts.contentUnits.length,
          assetCount: params.artifacts.assets.length,
          embeddingCount: params.artifacts.contentUnits.length,
        },
        null,
        2,
      ),
    );
    await params.storage.put(
      buildTextbookStorageKey({
        syllabus: "sslc",
        subjectSlug: params.options.subjectCode,
        medium: params.options.medium,
        versionLabel: params.options.versionLabel,
        kind: "processed",
        fileName: "manifest.json",
      }),
      JSON.stringify(
        {
          textbookVersionId: version.id,
          sourceUrl: params.options.sourceUrl ?? null,
          versionLabel: params.options.versionLabel,
          title: params.options.title ?? textbook.title,
          partLabel: params.options.partLabel ?? null,
          pageCount: params.artifacts.pages.length,
          chapterCount: params.artifacts.chapters.length,
          contentUnitCount: params.artifacts.contentUnits.length,
          assetCount: params.artifacts.assets.length,
          embeddingCount: params.artifacts.contentUnits.length,
          checksumSha256: params.checksum,
          tocDetection: params.tocEvidence,
          generatedAt: new Date().toISOString(),
        },
        null,
        2,
      ),
    );

    await params.prisma.textbookVersion.updateMany({
      where: {
        textbookId: textbook.id,
        id: { not: version.id },
      },
      data: {
        isActive: false,
      },
    });

    await params.prisma.textbookVersion.update({
      where: { id: version.id },
      data: {
        status: "published",
        isActive: true,
        metadata: {
          pipeline: "local_textbook_pipeline",
          chaptersDetected: params.artifacts.chapters.length,
          assetsDetected: params.artifacts.assets.length,
          embeddingsStored: params.artifacts.contentUnits.length,
          partLabel: params.options.partLabel ?? null,
        },
      },
    });

    await updateIngestionJob(params.prisma, job.id, "published", "completed", {
      pageCount: params.artifacts.pages.length,
      chapterCount: params.artifacts.chapters.length,
      contentUnitCount: params.artifacts.contentUnits.length,
      assetCount: params.artifacts.assets.length,
      questionCount: params.artifacts.questions.length,
    });

    return {
      jobId: job.id,
      textbookVersionId: version.id,
      pageCount: params.artifacts.pages.length,
      chapterCount: params.artifacts.chapters.length,
      contentUnitCount: params.artifacts.contentUnits.length,
      assetCount: params.artifacts.assets.length,
      exerciseCount: params.artifacts.exercises.length,
      questionCount: params.artifacts.questions.length,
      storagePrefix: buildTextbookStorageKey({
        syllabus: "sslc",
        subjectSlug: params.options.subjectCode,
        medium: params.options.medium,
        versionLabel: params.options.versionLabel,
        kind: "processed",
        fileName: "",
      }),
      chapters: params.artifacts.chapters,
    } satisfies TextbookPipelineResult;
  } catch (error) {
    await updateIngestionJob(
      params.prisma,
      job.id,
      "parsed",
      "failed",
      undefined,
      error instanceof Error ? error.message : String(error),
    );
    throw error;
  }
}

export async function runLocalTextbookPipeline(params: {
  prisma: PrismaClient;
  storage?: StorageAdapter;
  embedding: TextbookPipelineEmbeddingAdapter;
  options: TextbookPipelineOptions;
}) {
  if (params.options.sourceUrl) {
    const hostname = new URL(params.options.sourceUrl).hostname;
    if (
      params.options.sourceType === "official_download" &&
      !APPROVED_TEXTBOOK_SOURCE_DOMAINS.includes(hostname as (typeof APPROVED_TEXTBOOK_SOURCE_DOMAINS)[number])
    ) {
      throw new Error("Source URL domain is not approved for official download metadata.");
    }
  }

  const storage = params.storage ?? new LocalStorageAdapter();
  const buffer = await readFile(params.options.pdfPath);
  const checksum = createHash("sha256").update(buffer).digest("hex");
  console.log(
    `[pipeline] start ${params.options.subjectCode}/${params.options.medium}/${params.options.versionLabel} from ${params.options.pdfPath}`,
  );

  await clearVersionStorage({
    subjectCode: params.options.subjectCode,
    medium: params.options.medium,
    versionLabel: params.options.versionLabel,
  });
  console.log(`[pipeline] cleared storage for ${params.options.subjectCode}/${params.options.medium}/${params.options.versionLabel}`);

  const { rawPdfPath } = await persistRawPdf({
    options: params.options,
    checksum,
    buffer,
    storage,
  });
  console.log(`[pipeline] saved raw pdf -> ${rawPdfPath}`);

  const pages = await extractPdfPagesFromFile(params.options.pdfPath, params.embedding, params.options.medium);
  console.log(
    `[pipeline] extracted ${pages.length} pages (${pages.filter((page) => page.ocrUsed).length} OCR fallback)`,
  );
  const tempDir = path.join(os.tmpdir(), `right-answer-toc-${randomUUID()}`);
  await mkdir(tempDir, { recursive: true });

  try {
    console.log("[pipeline] resolving chapter index");
    const { chapters, evidence } = await resolveChapterDetection({
      pdfPath: params.options.pdfPath,
      pages,
      outputDir: tempDir,
      chromePath: params.options.chromePath,
      tocScanPages: params.options.tocScanPages,
      forceCodexToc: params.options.forceCodexToc,
      interactiveConfirm: params.options.interactiveConfirm,
      indexPages: params.options.indexPages,
      manualChapters: params.options.manualChapters,
    });
    console.log(`[pipeline] resolved ${chapters.length} chapters`);
    const realChapters = chapters.filter((chapter) => chapter.chapterNumber > 0);
    if (realChapters.length === 0) {
      throw new Error(
        `No textbook chapters were detected for ${params.options.subjectCode}/${params.options.medium}/${params.options.versionLabel}.`,
      );
    }

    console.log("[pipeline] building processed artifacts");
    const artifacts = await buildProcessedArtifacts({
      pdfPath: params.options.pdfPath,
      pages,
      chapters,
      subjectCode: params.options.subjectCode,
      medium: params.options.medium,
      versionLabel: params.options.versionLabel,
      chromePath: params.options.chromePath,
      keepDebugArtifacts: params.options.keepDebugArtifacts,
      embedding: params.embedding,
    });
    console.log(
      `[pipeline] built artifacts (${artifacts.contentUnits.length} content units, ${artifacts.assets.length} assets, ${artifacts.questions.length} questions)`,
    );
    if (artifacts.contentUnits.length === 0) {
      throw new Error(
        `No content units were generated for ${params.options.subjectCode}/${params.options.medium}/${params.options.versionLabel}.`,
      );
    }

    console.log("[pipeline] persisting processed textbook");
    return persistProcessedTextbook({
      prisma: params.prisma,
      storage,
      embedding: params.embedding,
      options: params.options,
      checksum,
      rawPdfPath,
      artifacts,
      tocEvidence: evidence,
    });
  } finally {
    if (!params.options.keepDebugArtifacts) {
      await rm(tempDir, { recursive: true, force: true });
    }
  }
}

export async function writeChapterDetectionPreview(params: {
  pdfPath: string;
  outputPath: string;
  embedding: TextbookPipelineEmbeddingAdapter;
  chromePath?: string;
  tocScanPages?: number;
  forceCodexToc?: boolean;
  interactiveConfirm?: boolean;
  indexPages?: number[];
  manualChapters?: ManualChapterInput[];
}) {
  const pages = await extractPdfPagesFromFile(params.pdfPath, params.embedding);
  const tempDir = path.join(os.tmpdir(), `right-answer-preview-${randomUUID()}`);
  await mkdir(tempDir, { recursive: true });

  try {
    const detection = await resolveChapterDetection({
      pdfPath: params.pdfPath,
      pages,
      outputDir: tempDir,
      chromePath: params.chromePath,
      tocScanPages: params.tocScanPages,
      forceCodexToc: params.forceCodexToc,
      interactiveConfirm: params.interactiveConfirm,
      indexPages: params.indexPages,
      manualChapters: params.manualChapters,
    });

    await mkdir(path.dirname(params.outputPath), { recursive: true });
    await writeFile(
      params.outputPath,
      JSON.stringify(
        {
          pdfPath: params.pdfPath,
          pages: pages.map((page) => ({
            pdfPageNumber: page.pdfPageNumber,
            charCount: page.charCount,
            tocScore: page.tocScore,
            likelyImagePage: page.likelyImagePage,
          })),
          detection,
        },
        null,
        2,
      ),
    );
    return detection;
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}
