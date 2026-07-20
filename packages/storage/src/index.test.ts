import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";

import { LocalStorageAdapter } from "./index";

test("LocalStorageAdapter writes and reads content", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "ra-storage-"));
  const storage = new LocalStorageAdapter(root);

  try {
    await storage.put("cache/exact/example.json", JSON.stringify({ ok: true }));
    const buffer = await storage.get("cache/exact/example.json");
    assert.equal(buffer.toString("utf8"), JSON.stringify({ ok: true }));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
