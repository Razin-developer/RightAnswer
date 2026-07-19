import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

import { prisma } from "@right-answer/database";

import { EmbeddingService } from "../src/modules/common/embedding.service";
import { parsePipelineCliArgs } from "../src/modules/ingestion/local-textbook-pipeline";

export function loadLocalEnvFile() {
  const envPath = path.resolve(process.cwd(), ".env");
  if (!existsSync(envPath)) {
    return;
  }

  const raw = readFileSync(envPath, "utf8");
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const delimiterIndex = trimmed.indexOf("=");
    if (delimiterIndex === -1) continue;

    const key = trimmed.slice(0, delimiterIndex).trim();
    const value = trimmed.slice(delimiterIndex + 1).trim();
    if (!(key in process.env)) {
      process.env[key] = value;
    }
  }
}

export function getScriptContext(argv: string[]) {
  loadLocalEnvFile();
  return {
    prisma,
    embedding: new EmbeddingService(),
    options: parsePipelineCliArgs(argv),
  };
}
