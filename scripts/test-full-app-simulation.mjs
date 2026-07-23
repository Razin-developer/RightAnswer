#!/usr/bin/env node
/**
 * Full-system, no-UI simulation of every user action the app supports,
 * run against a live instance of apps/api — the same requests the Flutter
 * client makes, replayed directly. Validates that every action a user can
 * take actually round-trips correctly between this device's would-be
 * local SQLite and the server's Postgres: push it, then re-fetch it as if
 * the app were reopened, and deep-compare the two.
 *
 * Covers: auth, unauthenticated-endpoint rejection, plans/usage, chat
 * (AI call + rename + sharing), exams (AI-generated method + manually-
 * authored method), study plans (AI-generated method + manually-scheduled
 * method), an explicit "app reopen" pull simulation, content sharing, and
 * mock payment / plan upgrade.
 *
 * Run:
 *   node scripts/test-full-app-simulation.mjs
 *   node scripts/test-full-app-simulation.mjs --base-url http://localhost:4000
 *   BASE_URL=https://razin.hackclub.app node scripts/test-full-app-simulation.mjs
 *
 * Makes a small number of real (metered) AI calls — kept deliberately few;
 * everything else is synthetic data pushed directly through the sync
 * endpoints, since the sync mechanism itself doesn't care where the data
 * came from.
 *
 * Exits non-zero if any step fails.
 */

import process from "node:process";

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--base-url" || arg === "--baseUrl") out.baseUrl = argv[++i];
    else if (arg.startsWith("--base-url=")) out.baseUrl = arg.slice("--base-url=".length);
  }
  return out;
}

const cliArgs = parseArgs(process.argv.slice(2));
const BASE_URL = (
  cliArgs.baseUrl ||
  process.env.BASE_URL ||
  process.env.API_BASE_URL ||
  "https://razin.hackclub.app"
).replace(/\/+$/, "");

console.log(`[config] BASE_URL = ${BASE_URL}`);

const results = [];
let token = null;

function record(name, ok, detail) {
  results.push({ name, ok, detail });
  console.log(`[${ok ? "PASS" : "FAIL"}] ${name}${detail ? " — " + detail : ""}`);
}

async function api(method, path, body, { auth = true } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (auth && token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${BASE_URL}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let json = null;
  try {
    json = await res.json();
  } catch {
    // non-JSON response — leave json null, caller checks res.ok
  }
  return { status: res.status, ok: res.ok, json };
}

async function step(name, fn) {
  try {
    await fn();
  } catch (error) {
    record(name, false, error?.message ?? String(error));
  }
}

/** True if every key/value in `expected` is present and equal in `actual`
 * (recursively for plain objects/arrays) — `actual` may have extra fields
 * the server adds (ids, timestamps) without failing the check. */
function matchesSubset(actual, expected) {
  if (expected === null || typeof expected !== "object") return actual === expected;
  if (Array.isArray(expected)) {
    if (!Array.isArray(actual) || actual.length !== expected.length) return false;
    return expected.every((item, i) => matchesSubset(actual[i], item));
  }
  if (actual === null || typeof actual !== "object") return false;
  return Object.entries(expected).every(([k, v]) => matchesSubset(actual[k], v));
}

function assertSubset(actual, expected, label) {
  if (!matchesSubset(actual, expected)) {
    throw new Error(`${label}: data mismatch after round trip.\n  expected⊆: ${JSON.stringify(expected)}\n  actual:    ${JSON.stringify(actual)}`);
  }
}

const stamp = Date.now();
const testEmail = `sim-test-${stamp}@rightanswer.test`;
const testPassword = "SimTest12345!";

let userId = null;
const chatLocalId = `sim-chat-${stamp}`;
const examLocalIdAi = `sim-exam-ai-${stamp}`;
const examLocalIdManual = `sim-exam-manual-${stamp}`;
const planLocalIdAi = `sim-plan-ai-${stamp}`;
const planLocalIdManual = `sim-plan-manual-${stamp}`;

// ── 1. Auth ──────────────────────────────────────────────────────────────

await step("register test user", async () => {
  const res = await api(
    "POST",
    "/api/auth/register",
    { email: testEmail, password: testPassword, name: "Simulation Test" },
    { auth: false },
  );
  if (!res.ok || !res.json?.data?.token) {
    throw new Error(`status=${res.status} body=${JSON.stringify(res.json)}`);
  }
  token = res.json.data.token;
  userId = res.json.data.user?.id;
  record("register test user", true, `user=${userId}`);
});

await step("duplicate registration is rejected", async () => {
  const res = await api(
    "POST",
    "/api/auth/register",
    { email: testEmail, password: testPassword, name: "Duplicate" },
    { auth: false },
  );
  if (res.ok) throw new Error(`expected failure, got status=${res.status}`);
  record("duplicate registration is rejected", true, `status=${res.status}`);
});

await step("login with correct credentials", async () => {
  const res = await api(
    "POST",
    "/api/auth/login",
    { email: testEmail, password: testPassword },
    { auth: false },
  );
  if (!res.ok || !res.json?.data?.token) throw new Error(`status=${res.status}`);
  token = res.json.data.token; // simulate the app re-logging-in on a fresh session
  record("login with correct credentials", true);
});

await step("login with wrong password is rejected", async () => {
  const res = await api(
    "POST",
    "/api/auth/login",
    { email: testEmail, password: "wrong-password" },
    { auth: false },
  );
  if (res.ok || res.status !== 401) throw new Error(`expected 401, got ${res.status}`);
  record("login with wrong password is rejected", true);
});

await step("GET /api/auth/me returns hobby plan by default", async () => {
  const res = await api("GET", "/api/auth/me");
  if (!res.ok) throw new Error(`status=${res.status}`);
  const plan = res.json?.data?.user?.plan;
  if (plan !== "hobby") throw new Error(`expected plan=hobby, got ${plan}`);
  record("GET /api/auth/me returns hobby plan by default", true);
});

await step("PUT /api/auth/me updates name", async () => {
  const res = await api("PUT", "/api/auth/me", { name: "Simulation Renamed" });
  if (!res.ok || res.json?.data?.user?.name !== "Simulation Renamed") {
    throw new Error(`status=${res.status} body=${JSON.stringify(res.json)}`);
  }
  record("PUT /api/auth/me updates name", true);
});

await step("change-password rejects wrong old password", async () => {
  const res = await api("POST", "/api/auth/change-password", {
    oldPassword: "definitely-wrong",
    newPassword: "NewPassword123!",
  });
  if (res.ok || res.status !== 401) throw new Error(`expected 401, got status=${res.status}`);
  record("change-password rejects wrong old password", true);
});

await step("change-password succeeds with correct old password", async () => {
  const res = await api("POST", "/api/auth/change-password", {
    oldPassword: testPassword,
    newPassword: "NewPassword123!",
  });
  if (!res.ok) throw new Error(`status=${res.status} body=${JSON.stringify(res.json)}`);
  record("change-password succeeds with correct old password", true);
});

await step("stale token from before password change still works (not revoked)", async () => {
  // Documents actual behavior: JWTs aren't revoked on password change. Not
  // a pass/fail correctness bug by itself, just recorded for visibility.
  const res = await api("GET", "/api/auth/me");
  record(
    "stale token from before password change still works (not revoked)",
    res.ok,
    res.ok ? "confirmed (expected JWT behavior)" : `status=${res.status}`,
  );
});

// ── 2. Unauthenticated AI endpoints are rejected ────────────────────────

for (const [path, body] of [
  ["/api/ai/chat", { question: "test" }],
  ["/api/ai/chat/stream", { question: "test" }],
  ["/api/ai/title", { message: "test" }],
  ["/api/ai/embeddings", { text: "test" }],
  ["/api/ai/rerank", { question: "test", documents: ["a", "b"] }],
]) {
  await step(`unauthenticated POST ${path} is rejected`, async () => {
    const res = await fetch(`${BASE_URL}${path}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (res.status !== 401) throw new Error(`expected 401, got ${res.status}`);
    record(`unauthenticated POST ${path} is rejected`, true);
  });
}

// ── 3. Plans / usage ─────────────────────────────────────────────────────

await step("GET /api/plans returns 3 tiers", async () => {
  const res = await api("GET", "/api/plans", undefined, { auth: false });
  const plans = res.json?.data?.plans;
  if (!res.ok || !Array.isArray(plans) || plans.length !== 3) {
    throw new Error(`status=${res.status} plans=${JSON.stringify(plans)}`);
  }
  const ids = plans.map((p) => p.id).sort().join(",");
  if (ids !== "hobby,pro,scholar") throw new Error(`unexpected plan ids: ${ids}`);
  record("GET /api/plans returns 3 tiers", true, ids);
});

await step("GET /api/usage/me reflects hobby limits", async () => {
  const res = await api("GET", "/api/usage/me");
  if (!res.ok) throw new Error(`status=${res.status} body=${JSON.stringify(res.json)}`);
  const usage = res.json.data;
  if (usage.plan !== "hobby" || typeof usage.dailyQuestionLimit !== "number") {
    throw new Error(`unexpected usage shape: ${JSON.stringify(usage)}`);
  }
  record("GET /api/usage/me reflects hobby limits", true, JSON.stringify(usage));
});

// ── 4. Chat: AI call, rename sync, sharing ──────────────────────────────

await step("POST /api/ai/chat returns a real answer", async () => {
  const res = await api("POST", "/api/ai/chat", {
    question: "In one sentence, what is photosynthesis?",
    responseLength: "small",
  });
  if (!res.ok) throw new Error(`status=${res.status} body=${JSON.stringify(res.json)}`);
  const content = res.json?.data?.content;
  if (!content || content.trim().length === 0) {
    throw new Error(`empty content: ${JSON.stringify(res.json?.data)}`);
  }
  record("POST /api/ai/chat returns a real answer", true, content.slice(0, 60) + "…");
});

await step("chat: create, sync round trip (list matches push)", async () => {
  const upsert = await api("POST", "/api/chats", {
    localId: chatLocalId,
    name: "Simulation Chat",
  });
  if (!upsert.ok) throw new Error(`upsert status=${upsert.status}`);

  // Simulate reopening the app: list chats and confirm what was just
  // pushed comes back with the same name.
  const list = await api("GET", "/api/chats");
  const found = list.json?.data?.chats?.find((c) => c.localId === chatLocalId);
  if (!list.ok || !found) throw new Error(`chat not found after push: ${JSON.stringify(list.json)}`);
  if (found.name !== "Simulation Chat") throw new Error(`name mismatch: ${found.name}`);
  record("chat: create, sync round trip (list matches push)", true);
});

await step("chat: rename via PUT persists (this route was previously missing entirely)", async () => {
  const rename = await api("PUT", `/api/chats/by-local/${chatLocalId}`, {
    name: "Renamed Simulation Chat",
  });
  if (!rename.ok) throw new Error(`rename status=${rename.status} body=${JSON.stringify(rename.json)}`);

  const list = await api("GET", "/api/chats");
  const found = list.json?.data?.chats?.find((c) => c.localId === chatLocalId);
  if (!found || found.name !== "Renamed Simulation Chat") {
    throw new Error(`rename did not persist: ${JSON.stringify(found)}`);
  }
  record("chat: rename via PUT persists (this route was previously missing entirely)", true);
});

await step("chat: add message via sync route (this route was previously missing entirely)", async () => {
  const msg = await api("POST", `/api/chats/by-local/${chatLocalId}/messages`, {
    localId: `${chatLocalId}-m1`,
    role: "user",
    content: "Simulated message",
  });
  if (!msg.ok) throw new Error(`message status=${msg.status} body=${JSON.stringify(msg.json)}`);
  record("chat: add message via sync route (this route was previously missing entirely)", true);
});

let chatShareToken = null;
await step("chat: share link created and resolves publicly", async () => {
  const share = await api("POST", `/api/chats/by-local/${chatLocalId}/share`, {
    accessLevel: "full",
  });
  if (!share.ok || !share.json?.data?.token) {
    throw new Error(`share status=${share.status} body=${JSON.stringify(share.json)}`);
  }
  chatShareToken = share.json.data.token;

  // Public resolution — deliberately no Authorization header, simulating
  // a different (unauthenticated) recipient opening the shared link.
  const resolved = await fetch(`${BASE_URL}/api/share/${chatShareToken}`);
  const resolvedJson = await resolved.json().catch(() => null);
  if (!resolved.ok) throw new Error(`resolve share status=${resolved.status}`);
  const messages = resolvedJson?.data?.messages;
  if (!Array.isArray(messages) || !messages.some((m) => m.content === "Simulated message")) {
    throw new Error(`shared chat missing pushed message: ${JSON.stringify(resolvedJson)}`);
  }
  record("chat: share link created and resolves publicly", true, `token=${chatShareToken}`);
});

// ── 5. Content sharing (exam/study-plan export ZIP upload) ─────────────

await step("content share: upload + public resolve returns identical bytes", async () => {
  const payload = Buffer.from(`simulation-content-${stamp}`, "utf8");
  const form = new FormData();
  form.append("file", new Blob([payload], { type: "application/zip" }), "simulation.zip");
  form.append("metadata", JSON.stringify({ kind: "simulation" }));

  const uploadRes = await fetch(`${BASE_URL}/api/content`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: form,
  });
  const uploadJson = await uploadRes.json().catch(() => null);
  if (!uploadRes.ok || !uploadJson?.data?.token) {
    throw new Error(`upload status=${uploadRes.status} body=${JSON.stringify(uploadJson)}`);
  }

  const resolveRes = await fetch(`${BASE_URL}/api/share/${uploadJson.data.token}`);
  if (!resolveRes.ok) throw new Error(`resolve status=${resolveRes.status}`);
  const bytesBack = Buffer.from(await resolveRes.arrayBuffer());
  if (!bytesBack.equals(payload)) {
    throw new Error(`downloaded content bytes do not match what was uploaded`);
  }
  record("content share: upload + public resolve returns identical bytes", true);
});

// ── 6. Exams — two creation methods ─────────────────────────────────────

let examJson = null;
await step("exam method A (AI-generated): AI call returns valid question JSON", async () => {
  const res = await api("POST", "/api/ai/chat", {
    question: "Generate 2 questions.",
    systemPrompt:
      'You are an expert exam creator. Return ONLY valid JSON: {"title": "...", "questions": [{"id":"1","type":"mcq","question":"...","options":["A","B","C","D"],"correctAnswer":"A","explanation":"..."}]}',
    responseFormat: "json",
  });
  if (!res.ok) throw new Error(`status=${res.status} body=${JSON.stringify(res.json)}`);
  examJson = JSON.parse(res.json?.data?.content);
  if (!Array.isArray(examJson.questions) || examJson.questions.length === 0) {
    throw new Error(`no questions parsed`);
  }
  record("exam method A (AI-generated): AI call returns valid question JSON", true, `${examJson.questions.length} questions`);
});

await step("exam method A (AI-generated): sync push/pull matches exactly", async () => {
  const payload = {
    exam: { id: examLocalIdAi, name: examJson?.title ?? "AI Exam", type: "mcq" },
    questions: examJson?.questions ?? [],
  };
  const push = await api("PUT", `/api/exams/by-local/${examLocalIdAi}`, {
    name: examJson?.title ?? "AI Exam",
    data: payload,
  });
  if (!push.ok) throw new Error(`push status=${push.status} body=${JSON.stringify(push.json)}`);

  // "App reopen" pull.
  const list = await api("GET", "/api/exams");
  const found = list.json?.data?.exams?.find((e) => e.localId === examLocalIdAi);
  if (!list.ok || !found) throw new Error(`exam not found after push: ${JSON.stringify(list.json)}`);
  assertSubset(found.data, payload, "exam method A");
  record("exam method A (AI-generated): sync push/pull matches exactly", true);
});

await step("exam method B (manually authored, no AI): sync push/pull matches exactly", async () => {
  const payload = {
    exam: { id: examLocalIdManual, name: "Manually Authored Exam", type: "true_false" },
    questions: [
      {
        id: "q1",
        type: "true_false",
        question: "Water boils at 100°C at sea level.",
        options: ["True", "False"],
        correctAnswer: "True",
      },
    ],
  };
  const push = await api("PUT", `/api/exams/by-local/${examLocalIdManual}`, {
    name: "Manually Authored Exam",
    data: payload,
  });
  if (!push.ok) throw new Error(`push status=${push.status} body=${JSON.stringify(push.json)}`);

  const list = await api("GET", "/api/exams");
  const found = list.json?.data?.exams?.find((e) => e.localId === examLocalIdManual);
  if (!list.ok || !found) throw new Error(`exam not found after push`);
  assertSubset(found.data, payload, "exam method B");
  record("exam method B (manually authored, no AI): sync push/pull matches exactly", true);
});

await step("exam: edit (re-push same local_id) updates rather than duplicates", async () => {
  const push = await api("PUT", `/api/exams/by-local/${examLocalIdManual}`, {
    name: "Manually Authored Exam (edited)",
    data: { exam: { id: examLocalIdManual, name: "Manually Authored Exam (edited)" }, questions: [] },
  });
  if (!push.ok) throw new Error(`push status=${push.status}`);

  const list = await api("GET", "/api/exams");
  const matches = list.json?.data?.exams?.filter((e) => e.localId === examLocalIdManual) ?? [];
  if (matches.length !== 1) throw new Error(`expected exactly 1 row, found ${matches.length}`);
  if (matches[0].name !== "Manually Authored Exam (edited)") {
    throw new Error(`edit did not persist: ${JSON.stringify(matches[0])}`);
  }
  record("exam: edit (re-push same local_id) updates rather than duplicates", true);
});

await step("exam: delete removes it from the next pull", async () => {
  const del = await api("DELETE", `/api/exams/by-local/${examLocalIdAi}`);
  if (!del.ok) throw new Error(`delete status=${del.status}`);
  const list = await api("GET", "/api/exams");
  const stillThere = list.json?.data?.exams?.some((e) => e.localId === examLocalIdAi);
  if (stillThere) throw new Error(`exam still present after delete`);
  record("exam: delete removes it from the next pull", true);
});

// ── 7. Study plans — two creation methods ───────────────────────────────

let planJson = null;
await step("study plan method A (AI-generated): AI call returns valid JSON", async () => {
  const res = await api("POST", "/api/ai/chat", {
    question: "Generate my study plan for: Simulation Plan",
    systemPrompt:
      'You are an expert study planner. Return ONLY valid JSON: {"planName": "...", "days": [{"date": "2026-08-01", "tasks": [{"title": "...", "description": "...", "chapterName": "...", "durationMinutes": 60}]}]}',
    responseFormat: "json",
  });
  if (!res.ok) throw new Error(`status=${res.status} body=${JSON.stringify(res.json)}`);
  planJson = JSON.parse(res.json?.data?.content);
  if (!Array.isArray(planJson.days) || planJson.days.length === 0) {
    throw new Error(`no days parsed`);
  }
  record("study plan method A (AI-generated): AI call returns valid JSON", true, `${planJson.days.length} days`);
});

await step("study plan method A (AI-generated): sync push/pull matches exactly", async () => {
  const payload = {
    plan: { id: planLocalIdAi, name: planJson?.planName ?? "AI Plan", hoursPerDay: 2 },
    days: planJson?.days ?? [],
    tasks: [],
  };
  const push = await api("PUT", `/api/study-plans/by-local/${planLocalIdAi}`, {
    name: planJson?.planName ?? "AI Plan",
    data: payload,
  });
  if (!push.ok) throw new Error(`push status=${push.status} body=${JSON.stringify(push.json)}`);

  const list = await api("GET", "/api/study-plans");
  const found = list.json?.data?.studyPlans?.find((p) => p.localId === planLocalIdAi);
  if (!list.ok || !found) throw new Error(`plan not found after push`);
  assertSubset(found.data, payload, "study plan method A");
  record("study plan method A (AI-generated): sync push/pull matches exactly", true);
});

await step("study plan method B (manually scheduled, no AI): sync push/pull matches exactly", async () => {
  const payload = {
    plan: {
      id: planLocalIdManual,
      name: "Manually Scheduled Plan",
      freeDays: [6, 7],
      hoursPerDay: 3,
    },
    days: [{ id: "d1", planId: planLocalIdManual, date: "2026-08-10T00:00:00.000" }],
    tasks: [
      {
        id: "t1",
        planId: planLocalIdManual,
        dayId: "d1",
        title: "Revise Chapter 3",
        durationMinutes: 45,
      },
    ],
  };
  const push = await api("PUT", `/api/study-plans/by-local/${planLocalIdManual}`, {
    name: "Manually Scheduled Plan",
    data: payload,
  });
  if (!push.ok) throw new Error(`push status=${push.status} body=${JSON.stringify(push.json)}`);

  const list = await api("GET", "/api/study-plans");
  const found = list.json?.data?.studyPlans?.find((p) => p.localId === planLocalIdManual);
  if (!list.ok || !found) throw new Error(`plan not found after push`);
  assertSubset(found.data, payload, "study plan method B");
  record("study plan method B (manually scheduled, no AI): sync push/pull matches exactly", true);
});

await step("study plan: delete removes it from the next pull", async () => {
  const del = await api("DELETE", `/api/study-plans/by-local/${planLocalIdAi}`);
  if (!del.ok) throw new Error(`delete status=${del.status}`);
  const list = await api("GET", "/api/study-plans");
  const stillThere = list.json?.data?.studyPlans?.some((p) => p.localId === planLocalIdAi);
  if (stillThere) throw new Error(`plan still present after delete`);
  record("study plan: delete removes it from the next pull", true);
});

// ── 8. "App reopen" simulation — a fresh session pulls everything ──────

await step("app reopen: fresh session (new token) still sees all synced data", async () => {
  // Simulates the device's local SQLite being empty (reinstall / new
  // device) and the app pulling from the server on launch, exactly what
  // ExamSyncService.pullMissing / StudyPlanSyncService.pullMissing /
  // CloudSyncService do in the client.
  const loginRes = await api(
    "POST",
    "/api/auth/login",
    { email: testEmail, password: "NewPassword123!" },
    { auth: false },
  );
  if (!loginRes.ok) throw new Error(`re-login status=${loginRes.status}`);
  const freshToken = loginRes.json.data.token;

  const check = async (path, dataKey, predicate, label) => {
    const res = await fetch(`${BASE_URL}${path}`, {
      headers: { Authorization: `Bearer ${freshToken}` },
    });
    const json = await res.json().catch(() => null);
    const items = json?.data?.[dataKey];
    if (!res.ok || !Array.isArray(items) || !items.some(predicate)) {
      throw new Error(`${label} missing on reopen: ${JSON.stringify(json)}`);
    }
  };

  await check("/api/chats", "chats", (c) => c.localId === chatLocalId, "chat");
  await check("/api/exams", "exams", (e) => e.localId === examLocalIdManual, "exam");
  await check(
    "/api/study-plans",
    "studyPlans",
    (p) => p.localId === planLocalIdManual,
    "study plan",
  );
  record("app reopen: fresh session (new token) still sees all synced data", true);
});

// ── 9. Mock payment / plan upgrade ───────────────────────────────────────

await step("mock payment upgrades plan to pro", async () => {
  const checkout = await api("POST", "/api/plans/checkout", { plan: "pro" });
  if (!checkout.ok || !checkout.json?.data?.payment?.id) {
    throw new Error(`checkout status=${checkout.status} body=${JSON.stringify(checkout.json)}`);
  }
  const paymentId = checkout.json.data.payment.id;

  const complete = await api("POST", `/api/plans/payments/${paymentId}/complete`, {
    status: "success",
  });
  if (!complete.ok) throw new Error(`complete status=${complete.status} body=${JSON.stringify(complete.json)}`);

  const me = await api("GET", "/api/auth/me");
  if (me.json?.data?.user?.plan !== "pro") {
    throw new Error(`plan not upgraded: ${JSON.stringify(me.json?.data?.user)}`);
  }
  record("mock payment upgrades plan to pro", true);
});

await step("paying twice for the same pending payment is idempotent (second call is a no-op)", async () => {
  const checkout = await api("POST", "/api/plans/checkout", { plan: "scholar" });
  const paymentId = checkout.json?.data?.payment?.id;
  if (!checkout.ok || !paymentId) throw new Error(`checkout status=${checkout.status}`);

  const first = await api("POST", `/api/plans/payments/${paymentId}/complete`, { status: "success" });
  if (!first.ok) throw new Error(`first complete status=${first.status}`);

  const second = await api("POST", `/api/plans/payments/${paymentId}/complete`, { status: "success" });
  if (second.ok) throw new Error(`expected second completion to be rejected, got ${second.status}`);

  const me = await api("GET", "/api/auth/me");
  if (me.json?.data?.user?.plan !== "scholar") {
    throw new Error(`plan not upgraded: ${JSON.stringify(me.json?.data?.user)}`);
  }
  record("paying twice for the same pending payment is idempotent (second call is a no-op)", true);
});

await step("failed mock payment does not change plan", async () => {
  const checkout = await api("POST", "/api/plans/checkout", { plan: "pro" });
  const paymentId = checkout.json?.data?.payment?.id;
  if (!checkout.ok || !paymentId) throw new Error(`checkout status=${checkout.status}`);

  const complete = await api("POST", `/api/plans/payments/${paymentId}/complete`, { status: "failed" });
  if (!complete.ok) throw new Error(`complete status=${complete.status}`);

  const me = await api("GET", "/api/auth/me");
  if (me.json?.data?.user?.plan !== "scholar") {
    throw new Error(`plan unexpectedly changed: ${JSON.stringify(me.json?.data?.user)}`);
  }
  record("failed mock payment does not change plan", true);
});

// ── Summary ───────────────────────────────────────────────────────────────

const failed = results.filter((r) => !r.ok);
console.log("\n──────── Summary ────────");
console.log(`${results.length - failed.length}/${results.length} passed`);
if (failed.length > 0) {
  console.log("\nFailed steps:");
  for (const f of failed) console.log(`  - ${f.name}: ${f.detail}`);
  console.log(`\nTest user left on server for inspection: ${testEmail}`);
  process.exit(1);
} else {
  console.log(
    `\nAll steps passed. Test user: ${testEmail} (harmless to leave — hobby-tier throwaway account, now on 'scholar' from the mock-payment steps).`,
  );
  process.exit(0);
}
