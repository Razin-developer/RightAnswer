import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

import { STORAGE_ROOT } from "@right-answer/config";

export interface StorageAdapter {
  put(logicalPath: string, contents: string | Buffer): Promise<string>;
  get(logicalPath: string): Promise<Buffer>;
  exists(logicalPath: string): Promise<boolean>;
  list(prefix: string): Promise<string[]>;
}

export class LocalStorageAdapter implements StorageAdapter {
  constructor(private readonly root = path.resolve(process.cwd(), STORAGE_ROOT)) {}

  private resolvePath(logicalPath: string) {
    return path.resolve(this.root, logicalPath);
  }

  async put(logicalPath: string, contents: string | Buffer) {
    const resolved = this.resolvePath(logicalPath);
    await mkdir(path.dirname(resolved), { recursive: true });
    await writeFile(resolved, contents);
    return resolved;
  }

  async get(logicalPath: string) {
    return readFile(this.resolvePath(logicalPath));
  }

  async exists(logicalPath: string) {
    try {
      await readFile(this.resolvePath(logicalPath));
      return true;
    } catch {
      return false;
    }
  }

  async list(prefix: string) {
    const resolved = this.resolvePath(prefix);
    try {
      const entries = await readdir(resolved, { recursive: true });
      return entries.map((entry) => path.join(prefix, entry.toString()));
    } catch {
      return [];
    }
  }
}

export function buildTextbookStorageKey(params: {
  syllabus: string;
  subjectSlug: string;
  medium: string;
  versionLabel: string;
  kind: "raw" | "processed";
  fileName: string;
}) {
  return path.join(
    "textbooks",
    params.kind,
    params.syllabus.toLowerCase(),
    params.subjectSlug,
    params.medium,
    params.versionLabel,
    params.fileName,
  );
}
