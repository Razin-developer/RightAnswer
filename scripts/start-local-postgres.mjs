import process from "node:process";
import path from "node:path";
import { access, readFile, rm } from "node:fs/promises";

import EmbeddedPostgres from "embedded-postgres";

const databaseDir = path.resolve(process.cwd(), "storage", "local-postgres");
const port = Number(process.env.LOCAL_POSTGRES_PORT ?? 5432);
const user = process.env.LOCAL_POSTGRES_USER ?? "postgres";
const password = process.env.LOCAL_POSTGRES_PASSWORD ?? "postgres";
const databaseName = process.env.LOCAL_POSTGRES_DB ?? "right_answer";

const postgres = new EmbeddedPostgres({
  databaseDir,
  user,
  password,
  port,
  persistent: true,
  initdbFlags: ["--encoding=UTF8", "--locale=C"],
  onLog(message) {
    console.log(`[local-postgres] ${String(message)}`);
  },
  onError(message) {
    console.error(`[local-postgres] ${String(message)}`);
  },
});

let shuttingDown = false;

async function pathExists(targetPath) {
  try {
    await access(targetPath);
    return true;
  } catch {
    return false;
  }
}

async function cleanupStalePidFile() {
  const pidPath = path.join(databaseDir, "postmaster.pid");
  if (!(await pathExists(pidPath))) {
    return;
  }

  try {
    const pidFile = await readFile(pidPath, "utf8");
    const [pidLine] = pidFile.split(/\r?\n/);
    const pid = Number(pidLine?.trim());
    if (Number.isInteger(pid) && pid > 0) {
      try {
        process.kill(pid, 0);
        console.log(`[local-postgres] detected active postmaster pid ${pid}`);
        return;
      } catch {
        console.log(`[local-postgres] removing stale postmaster.pid for pid ${pid}`);
      }
    }
  } catch {
    console.log("[local-postgres] removing unreadable postmaster.pid");
  }

  await rm(pidPath, { force: true });
}

async function shutdown(signal) {
  if (shuttingDown) {
    return;
  }

  shuttingDown = true;
  console.log(`[local-postgres] stopping after ${signal}`);
  try {
    await postgres.stop();
  } finally {
    process.exit(0);
  }
}

process.on("SIGINT", () => {
  void shutdown("SIGINT");
});

process.on("SIGTERM", () => {
  void shutdown("SIGTERM");
});

try {
  const hasCluster = await pathExists(path.join(databaseDir, "PG_VERSION"));
  if (!hasCluster) {
    await postgres.initialise();
  } else {
    await cleanupStalePidFile();
  }
  await postgres.start();

  try {
    await postgres.createDatabase(databaseName);
    console.log(`[local-postgres] ensured database ${databaseName}`);
  } catch (error) {
    const message = String(error);
    if (!message.includes("already exists")) {
      throw error;
    }
    console.log(`[local-postgres] database ${databaseName} already exists`);
  }

  console.log(
    `[local-postgres] running on postgresql://${user}:${password}@localhost:${port}/${databaseName}`,
  );

  setInterval(() => {}, 60_000);
} catch (error) {
  console.error("[local-postgres] failed to start", error);
  process.exit(1);
}
