import process from "node:process";
import { createWriteStream } from "node:fs";
import { access, mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

async function importPg() {
  try {
    return await import("pg");
  } catch {
    const fallback = path.resolve(
      process.cwd(),
      "node_modules/.pnpm/pg@8.22.0/node_modules/pg/lib/index.js",
    );
    await access(fallback);
    return import(pathToFileURL(fallback).href);
  }
}

const { default: pg } = await importPg();
const { Client } = pg;

const databaseUrl =
  process.env.DATABASE_URL ?? "postgresql://postgres:postgres@localhost:5432/right_answer";
const outputPath = path.resolve(
  process.cwd(),
  process.env.SEED_SQL_PATH ?? "storage/seeds/postgres-textbook-seed.sql",
);
const metadataPath = path.resolve(
  process.cwd(),
  process.env.SEED_METADATA_PATH ?? "storage/seeds/postgres-textbook-seed.metadata.json",
);

const tables = [
  "Subject",
  "Textbook",
  "TextbookVersion",
  "Chapter",
  "Page",
  "ContentUnit",
  "TextbookAsset",
  "TableAsset",
  "GraphAsset",
  "DiagramAsset",
  "Exercise",
  "Question",
  "Embedding",
  "RetrievalLog",
  "IngestionJob",
];

const primitiveArrayTypes = new Set([
  "_text",
  "_uuid",
  "_int2",
  "_int4",
  "_int8",
  "_float4",
  "_float8",
  "_bool",
]);

function quoteIdent(value) {
  return `"${String(value).replaceAll('"', '""')}"`;
}

function csvCell(value) {
  if (value === null || value === undefined) {
    return "\\N";
  }
  const text = String(value);
  return `"${text.replaceAll('"', '""')}"`;
}

function postgresArrayLiteral(items) {
  if (!Array.isArray(items)) {
    return String(items);
  }
  return `{${items
    .map((item) => {
      if (item === null || item === undefined) {
        return "NULL";
      }
      const text = String(item).replaceAll("\\", "\\\\").replaceAll('"', '\\"');
      return `"${text}"`;
    })
    .join(",")}}`;
}

function serializeValue(value, column) {
  if (value === null || value === undefined) {
    return null;
  }
  if (Buffer.isBuffer(value)) {
    return `\\x${value.toString("hex")}`;
  }
  if (column.data_type === "json" || column.data_type === "jsonb") {
    return JSON.stringify(value);
  }
  if (primitiveArrayTypes.has(column.udt_name)) {
    return postgresArrayLiteral(value);
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (typeof value === "object") {
    return JSON.stringify(value);
  }
  return value;
}

async function write(stream, text) {
  if (!stream.write(text)) {
    await new Promise((resolve) => stream.once("drain", resolve));
  }
}

async function tableColumns(client, table) {
  const result = await client.query(
    `
      SELECT column_name, data_type, udt_name
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = $1
      ORDER BY ordinal_position
    `,
    [table],
  );
  return result.rows;
}

async function tableExists(client, table) {
  const result = await client.query("SELECT to_regclass($1) IS NOT NULL AS exists", [
    `public."${table}"`,
  ]);
  return Boolean(result.rows[0]?.exists);
}

async function exportTable(client, stream, table) {
  if (!(await tableExists(client, table))) {
    return { table, rows: 0, skipped: true };
  }

  const columns = await tableColumns(client, table);
  if (!columns.length) {
    return { table, rows: 0, skipped: true };
  }

  const columnNames = columns.map((column) => column.column_name);
  await write(
    stream,
    `\nCOPY ${quoteIdent(table)} (${columnNames.map(quoteIdent).join(", ")}) FROM stdin WITH (FORMAT csv, NULL '\\N');\n`,
  );

  const cursorName = `seed_${table.toLowerCase().replaceAll(/[^a-z0-9_]/g, "_")}`;
  await client.query("BEGIN");
  await client.query(
    `DECLARE ${quoteIdent(cursorName)} NO SCROLL CURSOR FOR SELECT ${columnNames
      .map(quoteIdent)
      .join(", ")} FROM ${quoteIdent(table)}`,
  );

  let exported = 0;
  while (true) {
    const result = await client.query(`FETCH 500 FROM ${quoteIdent(cursorName)}`);
    if (!result.rows.length) {
      break;
    }
    for (const row of result.rows) {
      const line = columns
        .map((column) => csvCell(serializeValue(row[column.column_name], column)))
        .join(",");
      await write(stream, `${line}\n`);
      exported += 1;
    }
  }

  await client.query(`CLOSE ${quoteIdent(cursorName)}`);
  await client.query("COMMIT");
  await write(stream, "\\.\n");
  return { table, rows: exported, skipped: false };
}

async function main() {
  await mkdir(path.dirname(outputPath), { recursive: true });
  const client = new Client({ connectionString: databaseUrl });
  await client.connect();

  const stream = createWriteStream(outputPath, { encoding: "utf8" });
  const migration = await readFile(
    path.resolve(process.cwd(), "packages/database/prisma/migrations/0001_init/migration.sql"),
    "utf8",
  );
  await write(stream, "-- RightAnswer textbook production seed\n");
  await write(stream, "-- Generated from local PostgreSQL. Do not edit manually.\n\n");
  await write(stream, "DROP SCHEMA IF EXISTS public CASCADE;\n");
  await write(stream, "CREATE SCHEMA public;\n\n");
  await write(stream, `${migration}\n\n`);
  await write(stream, "BEGIN;\n");
  await write(stream, "SET session_replication_role = replica;\n");
  await write(stream, `TRUNCATE ${tables.map(quoteIdent).join(", ")} CASCADE;\n`);
  await write(stream, "COMMIT;\n");

  const results = [];
  for (const table of tables) {
    const result = await exportTable(client, stream, table);
    results.push(result);
    console.log(`[seed] ${table}: ${result.skipped ? "skipped" : result.rows}`);
  }

  await write(stream, "\nANALYZE;\n");
  await new Promise((resolve, reject) => {
    stream.end((error) => (error ? reject(error) : resolve()));
  });
  await client.end();

  await writeFile(
    metadataPath,
    `${JSON.stringify(
      {
        generatedAt: new Date().toISOString(),
        outputPath: path.relative(process.cwd(), outputPath),
        databaseUrl: databaseUrl.replace(/:\/\/([^:]+):([^@]+)@/, "://$1:***@"),
        tables: results,
      },
      null,
      2,
    )}\n`,
  );
  console.log(`[seed] wrote ${outputPath}`);
  console.log(`[seed] wrote ${metadataPath}`);
}

main().catch(async (error) => {
  console.error(error);
  process.exit(1);
});
