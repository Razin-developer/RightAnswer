import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import path from "node:path";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";

import { Injectable } from "@nestjs/common";
import {
  DEFAULT_EMBEDDING_BACKEND,
  DEFAULT_EMBEDDING_DIMENSIONS,
  DEFAULT_EMBEDDING_MODEL,
} from "@right-answer/config";

@Injectable()
export class EmbeddingService {
  readonly dimensions = DEFAULT_EMBEDDING_DIMENSIONS;
  private readonly backend = DEFAULT_EMBEDDING_BACKEND;
  private readonly modelId = DEFAULT_EMBEDDING_MODEL;
  private readonly maxBatchSize = Number(process.env.RIGHT_ANSWER_EMBEDDING_BATCH_SIZE ?? "48");
  private readonly maxRequestsPerWorker = Number(process.env.RIGHT_ANSWER_EMBEDDING_MAX_REQUESTS_PER_WORKER ?? "8");
  private readonly allowFallback = process.env.RIGHT_ANSWER_EMBEDDING_ALLOW_FALLBACK !== "0";
  private worker?: ChildProcessWithoutNullStreams;
  private workerReadyPromise?: Promise<void>;
  private workerBuffer = "";
  private nextRequestId = 1;
  private requestsSinceWorkerStart = 0;
  private intentionalWorkerExit = false;
  private readonly pendingRequests = new Map<
    number,
    {
      resolve: (value: number[][]) => void;
      reject: (reason?: unknown) => void;
    }
  >();

  normalizeText(input: string) {
    return input
      .trim()
      .toLowerCase()
      .replace(/[^\p{L}\p{N}\s]/gu, " ")
      .replace(/\s+/g, " ")
      .trim();
  }

  async embedText(text: string, mode: "document" | "query" = "document") {
    const [embedding] = await this.embedTexts([text], mode);
    return embedding ?? [];
  }

  async embedTexts(texts: string[], mode: "document" | "query" = "document") {
    if (texts.length === 0) {
      return [] as number[][];
    }

    const normalizedInputs = texts.map((text) => {
      if (typeof text === "string") {
        return text;
      }
      if (text === null || text === undefined) {
        return "";
      }
      return String(text);
    });

    if (this.backend === "local-hash") {
      return normalizedInputs.map((text) => this.buildLocalHashEmbedding(text));
    }

    try {
      await this.ensureWorker();
      const responses: number[][] = [];
      for (let index = 0; index < normalizedInputs.length; index += this.maxBatchSize) {
        const batch = normalizedInputs.slice(index, index + this.maxBatchSize);
        const batchEmbeddings = await this.requestEmbeddings(batch, mode);
        responses.push(...batchEmbeddings);
        if (this.maxRequestsPerWorker > 0 && this.requestsSinceWorkerStart >= this.maxRequestsPerWorker) {
          await this.recycleWorker();
        }
      }
      return responses;
    } catch (error) {
      if (!this.allowFallback) {
        throw error;
      }

      console.warn(
        `[embedding] falling back to local-hash backend after Hugging Face worker failure: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
      return normalizedInputs.map((text) => this.buildLocalHashEmbedding(text));
    }
  }

  cosineSimilarity(a: number[], b: number[]) {
    const dot = a.reduce((sum, value, index) => sum + value * (b[index] ?? 0), 0);
    const magnitudeA = Math.sqrt(a.reduce((sum, value) => sum + value * value, 0));
    const magnitudeB = Math.sqrt(b.reduce((sum, value) => sum + value * value, 0));

    if (!magnitudeA || !magnitudeB) {
      return 0;
    }

    return dot / (magnitudeA * magnitudeB);
  }

  toVectorLiteral(values: number[]) {
    return `[${values.map((value) => value.toFixed(8)).join(",")}]`;
  }

  private buildLocalHashEmbedding(text: string) {
    const normalized = this.normalizeText(text);
    return Array.from({ length: this.dimensions }, (_, index) => {
      const digest = createHash("sha256").update(`${normalized}:${index}`).digest("hex");
      return Number.parseInt(digest.slice(0, 8), 16) / 0xffffffff;
    });
  }

  private async ensureWorker() {
    if (this.workerReadyPromise) {
      return this.workerReadyPromise;
    }

    this.workerReadyPromise = new Promise<void>((resolve, reject) => {
      let ready = false;
      const pythonConfig = this.resolvePythonCommand();
      const workerScriptPath = path.resolve(process.cwd(), "apps/api/python/qwen_embedding_worker.py");

      if (!existsSync(workerScriptPath)) {
        reject(new Error(`Embedding worker script not found at ${workerScriptPath}`));
        return;
      }

      const child = spawn(pythonConfig.command, [...pythonConfig.args, workerScriptPath], {
        cwd: process.cwd(),
        env: {
          ...process.env,
          PYTHONUNBUFFERED: "1",
          RIGHT_ANSWER_EMBEDDING_MODEL: this.modelId,
          RIGHT_ANSWER_EMBEDDING_DIMENSIONS: String(this.dimensions),
        },
      });

      this.worker = child;
      this.intentionalWorkerExit = false;
      this.requestsSinceWorkerStart = 0;
      child.stdout.setEncoding("utf8");
      child.stderr.setEncoding("utf8");

      child.stdout.on("data", (chunk: string) => {
        ready = this.handleWorkerStdout(chunk, resolve, reject, ready);
      });

      child.stderr.on("data", (chunk: string) => {
        const message = chunk.trim();
        if (message) {
          console.warn(`[embedding-worker] ${message}`);
        }
      });

      child.on("error", (error) => {
        reject(error);
      });

      child.on("exit", (code, signal) => {
        const intentionalExit = this.intentionalWorkerExit;
        const error = new Error(
          `Embedding worker exited unexpectedly with code ${code ?? "null"} and signal ${signal ?? "null"}`,
        );
        if (!ready && !intentionalExit) {
          reject(error);
        }
        if (!intentionalExit) {
          for (const pending of this.pendingRequests.values()) {
            pending.reject(error);
          }
        }
        this.pendingRequests.clear();
        this.worker = undefined;
        this.workerReadyPromise = undefined;
        this.intentionalWorkerExit = false;
      });
    });

    return this.workerReadyPromise;
  }

  private handleWorkerStdout(
    chunk: string,
    resolveReady: () => void,
    rejectReady: (reason?: unknown) => void,
    isReady: boolean,
  ) {
    this.workerBuffer += chunk;
    let newlineIndex = this.workerBuffer.indexOf("\n");
    while (newlineIndex >= 0) {
      const line = this.workerBuffer.slice(0, newlineIndex).trim();
      this.workerBuffer = this.workerBuffer.slice(newlineIndex + 1);
      if (line) {
        try {
          const payload = JSON.parse(line) as
            | { type: "ready"; dimensions: number }
            | { id: number; ok: boolean; embeddings?: number[][]; error?: string; traceback?: string };

          if ("type" in payload && payload.type === "ready") {
            if (!isReady) {
              resolveReady();
              isReady = true;
            }
          } else if ("id" in payload) {
            const pending = this.pendingRequests.get(payload.id);
            if (pending) {
              this.pendingRequests.delete(payload.id);
              if (payload.ok) {
                pending.resolve(payload.embeddings ?? []);
              } else {
                pending.reject(new Error(payload.traceback ?? payload.error ?? "Unknown embedding worker error"));
              }
            }
          }
        } catch (error) {
          rejectReady(error);
        }
      }
      newlineIndex = this.workerBuffer.indexOf("\n");
    }

    return isReady;
  }

  private requestEmbeddings(texts: string[], mode: "document" | "query") {
    if (!this.worker?.stdin.writable) {
      throw new Error("Embedding worker stdin is not writable");
    }

    const requestId = this.nextRequestId++;
    const payload = JSON.stringify({
      id: requestId,
      mode,
      texts,
    });

    const responsePromise = new Promise<number[][]>((resolve, reject) => {
      this.pendingRequests.set(requestId, { resolve, reject });
    });

    this.worker.stdin.write(`${payload}\n`);
    this.requestsSinceWorkerStart += 1;
    return responsePromise;
  }

  private async recycleWorker() {
    if (!this.worker) {
      return;
    }

    const workerToStop = this.worker;
    this.intentionalWorkerExit = true;
    this.worker = undefined;
    this.workerReadyPromise = undefined;
    this.workerBuffer = "";
    this.requestsSinceWorkerStart = 0;

    await new Promise<void>((resolve) => {
      workerToStop.once("exit", () => resolve());
      workerToStop.kill();
    });
  }

  private resolvePythonCommand() {
    const explicitPath = process.env.RIGHT_ANSWER_EMBEDDING_PYTHON?.trim();
    if (explicitPath) {
      return { command: explicitPath, args: [] as string[] };
    }

    const localVenvPython = path.resolve(process.cwd(), ".venv-qwen-embeddings", "Scripts", "python.exe");
    if (existsSync(localVenvPython)) {
      return { command: localVenvPython, args: [] as string[] };
    }

    return { command: "py", args: ["-3.12"] };
  }
}
