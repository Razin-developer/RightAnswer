import process from "node:process";
import path from "node:path";
import { spawn } from "node:child_process";
import { access, mkdir, readdir, writeFile } from "node:fs/promises";

const baseDir = path.resolve(process.cwd(), "storage", "local-qdrant");
const binRoot = path.join(baseDir, "bin");
const downloadDir = path.join(baseDir, "downloads");
const dataDir = path.join(baseDir, "data");
const httpPort = process.env.LOCAL_QDRANT_HTTP_PORT ?? "6333";
const grpcPort = process.env.LOCAL_QDRANT_GRPC_PORT ?? "6334";

async function pathExists(targetPath) {
  try {
    await access(targetPath);
    return true;
  } catch {
    return false;
  }
}

async function latestWindowsAsset() {
  const response = await fetch("https://api.github.com/repos/qdrant/qdrant/releases/latest", {
    headers: { "User-Agent": "RightAnswer-local-qdrant" },
  });
  if (!response.ok) {
    throw new Error(`GitHub release lookup failed: ${response.status} ${await response.text()}`);
  }
  const release = await response.json();
  const asset = release.assets?.find((item) => item.name?.endsWith("windows-msvc.zip"));
  if (!asset?.browser_download_url) {
    throw new Error(`No Windows Qdrant asset found for ${release.tag_name ?? "latest release"}`);
  }
  return {
    version: release.tag_name,
    name: asset.name,
    url: asset.browser_download_url,
  };
}

async function findExecutable(root) {
  const entries = await readdir(root, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(root, entry.name);
    if (entry.isDirectory()) {
      const nested = await findExecutable(fullPath);
      if (nested) {
        return nested;
      }
    } else if (entry.name.toLowerCase() === "qdrant.exe") {
      return fullPath;
    }
  }
  return null;
}

async function run(command, args) {
  await new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: "inherit" });
    child.on("exit", (code) => {
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(`${command} exited with code ${code}`));
      }
    });
    child.on("error", reject);
  });
}

function psQuote(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

async function ensureQdrant() {
  await mkdir(binRoot, { recursive: true });
  await mkdir(downloadDir, { recursive: true });
  await mkdir(dataDir, { recursive: true });

  const asset = await latestWindowsAsset();
  const versionDir = path.join(binRoot, asset.version);
  const existingExe = (await pathExists(versionDir)) ? await findExecutable(versionDir) : null;
  if (existingExe) {
    return existingExe;
  }

  await mkdir(versionDir, { recursive: true });
  const zipPath = path.join(downloadDir, asset.name);
  if (!(await pathExists(zipPath))) {
    console.log(`[local-qdrant] downloading ${asset.version} from ${asset.url}`);
    const response = await fetch(asset.url, {
      headers: { "User-Agent": "RightAnswer-local-qdrant" },
    });
    if (!response.ok) {
      throw new Error(`Qdrant download failed: ${response.status} ${await response.text()}`);
    }
    const buffer = Buffer.from(await response.arrayBuffer());
    await writeFile(zipPath, buffer);
  }

  console.log(`[local-qdrant] extracting ${zipPath}`);
  await run("powershell", [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-Command",
    `Expand-Archive -LiteralPath ${psQuote(zipPath)} -DestinationPath ${psQuote(versionDir)} -Force`,
  ]);

  const exe = await findExecutable(versionDir);
  if (!exe) {
    throw new Error(`qdrant.exe was not found after extracting ${zipPath}`);
  }
  return exe;
}

try {
  const qdrantExe = await ensureQdrant();
  console.log(`[local-qdrant] running on http://localhost:${httpPort}`);
  console.log(`[local-qdrant] storage ${dataDir}`);
  const child = spawn(qdrantExe, [], {
    cwd: baseDir,
    stdio: "inherit",
    env: {
      ...process.env,
      QDRANT__SERVICE__HTTP_PORT: httpPort,
      QDRANT__SERVICE__GRPC_PORT: grpcPort,
      QDRANT__STORAGE__STORAGE_PATH: dataDir,
    },
  });

  const shutdown = (signal) => {
    console.log(`[local-qdrant] stopping after ${signal}`);
    child.kill(signal);
  };
  process.on("SIGINT", () => shutdown("SIGINT"));
  process.on("SIGTERM", () => shutdown("SIGTERM"));
  child.on("exit", (code) => process.exit(code ?? 0));
  child.on("error", (error) => {
    console.error("[local-qdrant] failed to start", error);
    process.exit(1);
  });
} catch (error) {
  console.error("[local-qdrant] failed", error);
  process.exit(1);
}
