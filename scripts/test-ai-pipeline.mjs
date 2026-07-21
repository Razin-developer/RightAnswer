#!/usr/bin/env node
/**
 * End-to-end smoke test for the Right Answer AI response pipeline
 * (POST /api/ai/chat), run against a live instance of apps/api.
 *
 * Run:
 *   node scripts/test-ai-pipeline.mjs
 *   node scripts/test-ai-pipeline.mjs --base-url http://localhost:8787
 *   BASE_URL=http://localhost:8787 node scripts/test-ai-pipeline.mjs
 *
 * Defaults to the live deployment (https://razin.hackclub.app). Each test
 * case makes real (metered) AI provider calls, so the case list is kept
 * small and deliberate — do not loop this into a large sweep.
 *
 * What it covers (see README-level task description for full context):
 *   1. Basic English generation — sane, non-JSON `content`.
 *   2. Malayalam generation — real Malayalam text, not empty/raw-JSON.
 *   3. Exact-cache + semantic-cache behavior.
 *   4. Non-empty `sources` on every successful answer.
 *   5. Beta-chapter confirmation gate + confirmBetaChapterId bypass.
 *   6. Response-time sanity check on the beta-gate peek (informational).
 *
 * Exits non-zero if any hard-fail occurred.
 */

import process from "node:process";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--base-url" || arg === "--baseUrl") {
      out.baseUrl = argv[++i];
    } else if (arg.startsWith("--base-url=")) {
      out.baseUrl = arg.slice("--base-url=".length);
    }
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

// ---------------------------------------------------------------------------
// Known-good / known-excluded test data.
//
// These IDs/topics were pulled from a real database snapshot (the local
// dev Postgres restored from the shared seed, same content as production)
// via direct SQL against Chapter/Subject/Textbook/ContentUnit, cross-checked
// against GET /api/catalog on the live server. Nothing here is fabricated.
// ---------------------------------------------------------------------------

// GET /api/catalog -> subjects[code=physics].chapters[number=1]
const ENGLISH_CHAPTER = {
  subjectCode: "physics",
  subjectName: "Physics",
  chapterId: "460188b3-8e7a-4ddd-bd30-37548dba36ab",
  chapterName: "Refraction of Light",
};
const ENGLISH_QUESTION = "What are the laws of refraction of light?";

// GET /api/catalog -> subjects[code=malayalam-at].chapters[number=3]
// (malayalam-at / malayalam-bt are the two subjects whose ml-medium content
// is enabled per content_policy.rs; this is a literature chapter, so the
// question is deliberately general rather than tied to exact wording.)
const MALAYALAM_CHAPTER = {
  subjectCode: "malayalam-at",
  subjectName: "Malayalam (AT)",
  chapterId: "0b5adea1-5c89-4494-aa00-db9677374ba8",
  chapterName: "വിശ്വലോകവീഥിനത്തിൽ",
};
const MALAYALAM_QUESTION =
  "വിശ്വലോകവീഥിനത്തിൽ എന്ന പാഠഭാഗത്തിന്റെ ആശയം ചുരുക്കി വിശദമാക്കാമോ?";

// From direct DB query: Chapter belonging to subject code "hindi", which
// content_policy.rs excludes entirely (EXCLUDED_SUBJECTS), regardless of
// medium. This chapter will NOT appear in GET /api/catalog.
const BETA_CHAPTER = {
  subjectCode: "hindi",
  subjectName: "Hindi",
  chapterId: "fce3db67-b8f6-4f87-836b-484c521c115f",
  chapterName: "हुआ आदमी (कविता)",
};
// The chapter is a poem ("पैदल चलता हुआ आदमी" / "The walking man") by
// Swapnil Shrivastava — content pulled straight from ContentUnit rows.
//
// A run-unique suffix is appended so repeated script runs don't collide
// with a previous run's *exact cache* entry for this question (see the
// exact-cache-vs-beta-gate finding documented next to test 5c below) — that
// would make the gate look like it "isn't triggering" when it's really just
// serving a cached answer from an earlier run's confirmed bypass.
const BETA_QUESTION_BASE =
  "हिंदी कविता 'पैदल चलता हुआ आदमी' में कवि 'निरीह' शब्द से क्या भाव व्यक्त करना चाहता है?";
const RUN_NONCE = String(Date.now());
const BETA_QUESTION = `${BETA_QUESTION_BASE} (प्रश्न ${RUN_NONCE})`;

// A semantically-similar-but-differently-worded rephrasing of
// ENGLISH_QUESTION, used to (informationally) probe the semantic cache.
const ENGLISH_QUESTION_REPHRASED =
  "Can you explain the rules that govern how light refracts?";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const results = [];
let hardFail = false;

function record(name, pass, detail, { hard = true } = {}) {
  results.push({ name, pass, detail, hard });
  if (!pass && hard) hardFail = true;
  const tag = pass ? "PASS" : hard ? "FAIL" : "INFO";
  console.log(`\n[${tag}] ${name}`);
  if (detail) console.log(detail);
}

async function postChat(body) {
  const start = Date.now();
  let res;
  let json;
  let text;
  try {
    res = await fetch(`${BASE_URL}/api/ai/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    text = await res.text();
    try {
      json = JSON.parse(text);
    } catch {
      json = null;
    }
  } catch (err) {
    return {
      ok: false,
      status: 0,
      elapsedMs: Date.now() - start,
      error: err instanceof Error ? err.message : String(err),
      raw: null,
      json: null,
    };
  }
  return {
    ok: res.ok,
    status: res.status,
    elapsedMs: Date.now() - start,
    raw: text,
    json,
  };
}

function looksLikeRawJsonBlob(content) {
  if (typeof content !== "string") return true;
  const trimmed = content.trim();
  if (trimmed.length === 0) return true;
  // A response that is (or starts with) a JSON object/array of the internal
  // envelope shape is the exact production bug we're checking for. Genuine
  // code samples in fenced blocks (```json ... ```) are fine; a *bare*
  // leading brace/bracket that parses as JSON is not.
  if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
    try {
      JSON.parse(trimmed);
      return true; // parses cleanly as JSON with nothing else around it
    } catch {
      // starts with { but isn't valid JSON on its own (e.g. markdown/math) - ok
      return false;
    }
  }
  return false;
}

function summarizeResponse(r) {
  const lines = [`  status=${r.status} elapsedMs=${r.elapsedMs}`];
  if (r.error) lines.push(`  transport error: ${r.error}`);
  if (r.json?.data) {
    const d = r.json.data;
    lines.push(`  servedFrom=${d.servedFrom ?? "(n/a)"}`);
    lines.push(`  needsBetaConfirmation=${d.needsBetaConfirmation ?? false}`);
    lines.push(`  chapterId=${d.chapterId ?? "(n/a)"} chapterName=${d.chapterName ?? "(n/a)"}`);
    lines.push(`  sources.length=${Array.isArray(d.sources) ? d.sources.length : "(n/a)"}`);
    const contentPreview =
      typeof d.content === "string" ? d.content.slice(0, 160).replace(/\n/g, " ") : String(d.content);
    lines.push(`  content preview: ${contentPreview}${d.content?.length > 160 ? "..." : ""}`);
  } else {
    lines.push(`  raw body (truncated): ${(r.raw ?? "").slice(0, 400)}`);
  }
  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// Test cases
// ---------------------------------------------------------------------------

async function testBasicEnglish() {
  const r = await postChat({ question: ENGLISH_QUESTION, responseLanguage: "English" });
  const d = r.json?.success ? r.json.data : null;
  const content = d?.content;
  const pass =
    r.ok &&
    !!d &&
    !d.needsBetaConfirmation &&
    typeof content === "string" &&
    content.trim().length > 0 &&
    !looksLikeRawJsonBlob(content);
  record(
    "1. Basic English generation",
    pass,
    summarizeResponse(r),
  );
  return { r, d };
}

async function testMalayalam() {
  // First try auto-retrieval (no chapterIds), the normal client path.
  const auto = await postChat({ question: MALAYALAM_QUESTION, responseLanguage: "Malayalam" });
  const autoD = auto.json?.success ? auto.json.data : null;

  if (autoD?.needsBetaConfirmation) {
    // MALAYALAM_CHAPTER is a genuinely enabled chapter per content_policy.rs
    // (malayalam-at ml-medium), so a beta-gate trip here means auto-retrieval's
    // top embedding match landed on a *different*, disabled chapter (e.g.
    // "Front Matter") instead of the intended enabled one. That's a retrieval
    // finding worth flagging, not a hard fail of "generation" itself — so we
    // note it, then retry scoped explicitly to the known-enabled chapter to
    // still validate that Malayalam generation itself works end-to-end.
    record(
      "2a. Malayalam auto-retrieval routed to enabled content (informational)",
      false,
      summarizeResponse(auto) +
        `\n  expected an answer scoped to enabled chapter ${MALAYALAM_CHAPTER.chapterName} (${MALAYALAM_CHAPTER.chapterId})` +
        `\n  instead the top embedding match was chapter "${autoD.chapterName}" (${autoD.chapterId}), which is disabled -> beta gate tripped.` +
        `\n  This means a legitimate, in-policy Malayalam question can be needlessly blocked by an` +
        ` unrelated top-1 embedding match (e.g. a Front Matter chapter). Retrying with explicit` +
        ` chapterIds to still validate core Malayalam generation below.`,
      { hard: false },
    );
  }

  const r = autoD?.needsBetaConfirmation
    ? await postChat({
        question: MALAYALAM_QUESTION,
        responseLanguage: "Malayalam",
        chapterIds: [MALAYALAM_CHAPTER.chapterId],
      })
    : auto;
  const d = r.json?.success ? r.json.data : null;
  const content = d?.content;
  const hasMalayalamScript = typeof content === "string" && /[ഀ-ൿ]/.test(content);
  const pass =
    r.ok &&
    !!d &&
    !d.needsBetaConfirmation &&
    typeof content === "string" &&
    content.trim().length > 0 &&
    !looksLikeRawJsonBlob(content) &&
    hasMalayalamScript;
  record(
    "2b. Malayalam generation produces real Malayalam content",
    pass,
    summarizeResponse(r) + `\n  containsMalayalamScript=${hasMalayalamScript}`,
  );
  return { r, d };
}

async function testCaching() {
  const body = { question: ENGLISH_QUESTION, responseLanguage: "English" };

  const first = await postChat(body);
  const firstD = first.json?.success ? first.json.data : null;

  const second = await postChat(body);
  const secondD = second.json?.success ? second.json.data : null;

  const exactCachePass =
    second.ok &&
    !!secondD &&
    secondD.servedFrom === "exact-cache" &&
    secondD.content === firstD?.content;

  record(
    "3a. Exact-cache hit on identical repeat request",
    exactCachePass,
    `First call servedFrom=${firstD?.servedFrom}\n` + summarizeResponse(second),
  );

  // Semantic cache probe — informational only, per task spec (embedding
  // similarity is probabilistic, so a miss here is not a hard failure).
  const third = await postChat({
    question: ENGLISH_QUESTION_REPHRASED,
    responseLanguage: "English",
  });
  const thirdD = third.json?.success ? third.json.data : null;
  const semanticHit = thirdD?.servedFrom === "semantic-cache";
  record(
    "3b. Semantic-cache probe (rephrased question)",
    semanticHit,
    summarizeResponse(third) +
      `\n  NOTE: informational only — a miss does not fail the suite (embedding similarity is probabilistic).`,
    { hard: false },
  );

  return { first, second, third };
}

async function testSourcesPresent(successfulResponses) {
  // Only applies to non-beta-gated answers — a needsBetaConfirmation
  // response has no content/sources by design, that's not a violation.
  const applicable = successfulResponses.filter(({ d }) => d && !d.needsBetaConfirmation);
  let pass = applicable.length > 0;
  const details = [];
  for (const { label, d } of applicable) {
    const sources = d?.sources;
    const ok =
      Array.isArray(sources) &&
      sources.length > 0 &&
      sources.every((s) => typeof s?.text === "string" && s.text.trim().length > 0);
    if (!ok) pass = false;
    details.push(
      `  [${label}] sources.length=${Array.isArray(sources) ? sources.length : "(n/a)"} ` +
        `firstTextPreview=${JSON.stringify(sources?.[0]?.text?.slice(0, 80) ?? null)}`,
    );
  }
  if (applicable.length === 0) {
    details.push("  no non-beta-gated responses were available to check");
  }
  record("4. Non-empty sources on every successful (non-beta-gated) answer", pass, details.join("\n"));
}

async function testBetaGate() {
  // A random, unused subjectId is included purely to force a fresh
  // exact-cache/semantic-cache partition for this run (see the cache_key /
  // lookup_semantic_cache signatures in apps/api/src/routes.rs — both are
  // partitioned by subjectId). Without this, a *previous* run's confirmed
  // beta-bypass answer (or even a semantically-similar answer from an
  // entirely unrelated earlier test, since embeddings for this Hindi
  // question turned out to land unexpectedly close to unrelated English
  // content — see the finding logged below) can be served from cache and
  // make the gate look broken when it's really just a caching side effect.
  const cacheBuster = crypto.randomUUID();
  const baseBody = { question: BETA_QUESTION, subjectId: cacheBuster };

  const gated = await postChat(baseBody);
  let gatedD = gated.json?.success ? gated.json.data : null;
  let gatePass =
    gated.ok &&
    !!gatedD &&
    gatedD.needsBetaConfirmation === true &&
    typeof gatedD.chapterId === "string" &&
    gatedD.chapterId.length > 0 &&
    typeof gatedD.chapterName === "string" &&
    gatedD.chapterName.length > 0 &&
    typeof gatedD.subjectName === "string" &&
    gatedD.subjectName.length > 0;

  record(
    "5a. Beta-chapter confirmation triggers via auto-retrieval (no chapterIds)",
    gatePass,
    summarizeResponse(gated) +
      `\n  expected chapter (from DB): ${BETA_CHAPTER.chapterName} / ${BETA_CHAPTER.subjectName}` +
      `\n  NOTE: relies on live deployment having the content-policy beta gate deployed.` +
      ` If this fails with a normal answer instead of needsBetaConfirmation, the` +
      ` deployed API may be older than the current apps/api/src/content_policy.rs.`,
  );

  // Sanity signal (informational): the beta-gate peek path in select_contexts
  // does an embeddings-only lookup, no rerank, no generation call. It should
  // come back meaningfully faster than a full answer (which does
  // embed + rerank + LLM generation). We can't observe "no rerank happened"
  // directly over HTTP, so we just report timing as a sanity signal.
  record(
    "6. Beta-gate peek response time (sanity signal, not a hard assertion)",
    true,
    `  beta-gate response time: ${gated.elapsedMs}ms (compare to full-answer timings logged above/below)`,
    { hard: false },
  );

  let effectiveBody = baseBody;
  if (!gatePass) {
    // FINDING: across repeated manual probes (Hindi-script phrasing,
    // English-phrasing referencing the same poem, and an unrelated Arabic-
    // medium chapter about a Rameshwaram/APJ-Abdul-Kalam theme), the
    // embeddings-only peek in select_contexts never surfaced the actual
    // excluded chapter as the top match — it kept landing on unrelated,
    // *enabled* English-medium chapters (whose chunk volume/embedding
    // quality apparently dominates the vector search) and answered
    // normally instead of gating. That means in practice, for a real user
    // typing a real question in Hindi/Arabic/Sanskrit/Urdu script, the beta
    // gate this endpoint relies on essentially never fires — the very
    // content it's meant to shield mostly loses the retrieval competition
    // to unrelated English content. This is a real gap worth fixing
    // upstream, not a flaw in this test.
    //
    // To still exercise the gate/bypass *mechanism* itself end-to-end (the
    // part of the contract this script can meaningfully assert), fall back
    // to explicitly scoping the request to the known-excluded chapter via
    // chapterIds — select_contexts uses that as the peek scope directly, so
    // the gate check runs against exactly that chapter.
    const scoped = await postChat({
      question: BETA_QUESTION,
      subjectId: cacheBuster,
      chapterIds: [BETA_CHAPTER.chapterId],
    });
    const scopedD = scoped.json?.success ? scoped.json.data : null;
    const scopedGatePass =
      scoped.ok &&
      !!scopedD &&
      scopedD.needsBetaConfirmation === true &&
      typeof scopedD.chapterId === "string" &&
      scopedD.chapterId.length > 0;
    record(
      "5a-fallback. Beta gate triggers when explicitly scoped to the excluded chapter",
      scopedGatePass,
      summarizeResponse(scoped) +
        `\n  This is a fallback check only, not the spec's "no chapterIds" auto-retrieval path` +
        ` (that path is covered — and found NOT to trigger in practice — by test 5a above).` +
        ` It isolates whether the gate mechanism itself (as opposed to retrieval ranking) is intact.`,
    );
    if (scopedGatePass) {
      gated.elapsedMs = scoped.elapsedMs;
      gatedD = scopedD;
      gatePass = true;
      effectiveBody = { question: BETA_QUESTION, subjectId: cacheBuster, chapterIds: [BETA_CHAPTER.chapterId] };
    }
  }

  if (!gatePass) {
    record(
      "5b. confirmBetaChapterId bypass",
      false,
      "  skipped — beta gate did not trigger in either 5a or the chapterIds-scoped fallback.",
    );
    return { gated, confirmed: null };
  }

  const confirmed = await postChat({
    ...effectiveBody,
    confirmBetaChapterId: gatedD.chapterId,
  });
  const confirmedD = confirmed.json?.success ? confirmed.json.data : null;
  const content = confirmedD?.content;
  const bypassPass =
    confirmed.ok &&
    !!confirmedD &&
    !confirmedD.needsBetaConfirmation &&
    typeof content === "string" &&
    content.trim().length > 0 &&
    !looksLikeRawJsonBlob(content);

  record(
    "5b. confirmBetaChapterId bypasses the gate with a real answer",
    bypassPass,
    summarizeResponse(confirmed),
  );

  if (bypassPass) {
    // Known-issue probe: the exact-answer cache is keyed on
    // question+language+responseLength+reasoningLevel+subjectId+chapterIds
    // (see apps/api/src/routes.rs::ai_chat / cache_key) — it does NOT
    // include confirmBetaChapterId, and the exact-cache lookup happens
    // *before* select_contexts (i.e. before the beta-gate check) runs at
    // all. So once a beta-gated question has been answered once via
    // confirmBetaChapterId, the exact-cache entry it creates will be
    // served for that same plain question afterwards — including to a
    // caller that never sent confirmBetaChapterId — silently bypassing
    // the beta gate for everyone from then on. This resends the exact
    // original gated request (no confirmBetaChapterId) and expects the
    // gate to still hold.
    const replay = await postChat(effectiveBody);
    const replayD = replay.json?.success ? replay.json.data : null;
    const gateStillHolds = replay.ok && !!replayD && replayD.needsBetaConfirmation === true;
    record(
      "5c. Beta gate still holds on repeat request after a confirmed bypass was cached",
      gateStillHolds,
      summarizeResponse(replay) +
        (gateStillHolds
          ? ""
          : `\n  BUG: the plain (unconfirmed) request was served the previously-cached,` +
            ` beta-bypassed answer (servedFrom=${replayD?.servedFrom}) instead of re-triggering` +
            ` needsBetaConfirmation. The exact-cache key does not account for confirmBetaChapterId` +
            ` and is checked before the beta-gate logic in select_contexts, so a single confirmed` +
            ` bypass permanently defeats the gate for that question for all future callers.`),
    );
  }

  return { gated, confirmed, confirmedD };
}

async function testCatalogReachable() {
  const start = Date.now();
  let res;
  let json;
  try {
    res = await fetch(`${BASE_URL}/api/catalog`);
    json = await res.json();
  } catch (err) {
    record(
      "0. GET /api/catalog reachable",
      false,
      `  transport error: ${err instanceof Error ? err.message : String(err)}`,
    );
    return null;
  }
  const subjects = json?.data?.subjects;
  const pass = res.ok && Array.isArray(subjects) && subjects.length > 0;
  record(
    "0. GET /api/catalog reachable",
    pass,
    `  status=${res.status} elapsedMs=${Date.now() - start} subjectCount=${subjects?.length ?? "(n/a)"}`,
  );
  return subjects;
}

// ---------------------------------------------------------------------------
// Run
// ---------------------------------------------------------------------------

async function main() {
  console.log("=".repeat(78));
  console.log("Right Answer AI pipeline end-to-end test");
  console.log("=".repeat(78));

  await testCatalogReachable();

  const { d: englishD } = await testBasicEnglish();
  const { d: malayalamD } = await testMalayalam();
  await testCaching();
  await testSourcesPresent(
    [
      { label: "english", d: englishD },
      { label: "malayalam", d: malayalamD },
    ].filter((entry) => entry.d),
  );
  await testBetaGate();

  console.log("\n" + "=".repeat(78));
  console.log("SUMMARY");
  console.log("=".repeat(78));
  for (const r of results) {
    const tag = r.pass ? "PASS" : r.hard ? "FAIL" : "INFO";
    console.log(`[${tag}] ${r.name}`);
  }
  const hardFailures = results.filter((r) => !r.pass && r.hard);
  const infoMisses = results.filter((r) => !r.pass && !r.hard);
  console.log(
    `\n${results.length} checks: ${results.length - hardFailures.length - infoMisses.length} pass, ` +
      `${hardFailures.length} hard-fail, ${infoMisses.length} informational-miss`,
  );

  if (hardFail) {
    console.error("\nRESULT: FAIL — one or more hard-fail checks failed.");
    process.exitCode = 1;
  } else {
    console.log("\nRESULT: PASS");
  }
}

main().catch((err) => {
  console.error("Unhandled error running test suite:", err);
  process.exitCode = 1;
});
