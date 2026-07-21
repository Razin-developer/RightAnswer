#!/usr/bin/env node
/**
 * Direct model-quality comparison: gemma vs qwen, fast vs reasoning tier,
 * across languages — bypasses the backend entirely (no retrieval, no
 * embeddings, no rerank, no textbook context). Every question is sent as a
 * bare prompt straight to the configured provider's /chat/completions, so
 * this measures raw model quality, not the RAG pipeline.
 *
 * Run:
 *   node scripts/test-model-quality.mjs
 *   node scripts/test-model-quality.mjs --method hackai   (default; or openrouter)
 *   node scripts/test-model-quality.mjs --out report.md
 *
 * Needs HACKAI_API_KEY or OPENROUTER_API_KEY in the environment (or a root
 * .env file) depending on --method / AI_METHOD.
 *
 * 11 questions (4 Malayalam, 2 English, 1 Arabic, 1 Urdu, 1 Sanskrit,
 * 2 Hindi) x 2 model families (gemma, qwen) x 2 tiers (fast, reasoning)
 * = 44 real, metered AI calls. This is a deliberate one-off quality
 * comparison, not something to loop or schedule.
 *
 * Writes a Markdown report (default: scripts/_model-quality-report.md)
 * with every response side by side per question, plus latency/token
 * stats — this script does not attempt to auto-score answer quality
 * (that's a subjective judgment call for a human reader), it only
 * collects the raw outputs so they can be compared directly.
 */

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import process from "node:process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..");

// ---------------------------------------------------------------------------
// Env loading (root .env, simple KEY=VALUE parser — no dependency needed)
// ---------------------------------------------------------------------------
function loadDotEnv(path) {
  if (!existsSync(path)) return;
  const lines = readFileSync(path, "utf8").split("\n");
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = value;
  }
}
loadDotEnv(join(repoRoot, ".env"));
loadDotEnv(join(repoRoot, ".env.production"));

// ---------------------------------------------------------------------------
// CLI args
// ---------------------------------------------------------------------------
const args = process.argv.slice(2);
function argValue(flag, fallback) {
  const idx = args.indexOf(flag);
  return idx !== -1 && args[idx + 1] ? args[idx + 1] : fallback;
}
const method = (
  argValue("--method", process.env.AI_METHOD) || "hackai"
).toLowerCase();
const outPath = argValue("--out", join(repoRoot, "scripts/_model-quality-report.md"));

const PROVIDERS = {
  hackai: {
    baseUrl: "https://ai.hackclub.com/proxy/v1",
    apiKey: process.env.HACKAI_API_KEY,
  },
  openrouter: {
    baseUrl: "https://openrouter.ai/api/v1",
    apiKey: process.env.OPENROUTER_API_KEY,
  },
};

const provider = PROVIDERS[method];
if (!provider) {
  console.error(`Unknown --method "${method}" (expected hackai or openrouter)`);
  process.exit(1);
}
if (!provider.apiKey) {
  console.error(
    `Missing API key for method=${method}. Set HACKAI_API_KEY or OPENROUTER_API_KEY ` +
      `(env var or root .env), or pass --method to pick the other provider.`
  );
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Model matrix
// ---------------------------------------------------------------------------
const MODELS = {
  gemma: {
    fast: "google/gemma-3-12b-it",
    reasoning: "google/gemma-4-31b-it",
  },
  qwen: {
    fast: "qwen/qwen3-8b",
    reasoning: "qwen/qwen3-14b",
  },
};

// ---------------------------------------------------------------------------
// Test questions: 4 Malayalam, 2 English, 1 Arabic, 1 Urdu, 1 Sanskrit, 2 Hindi
// Plain school-subject questions, deliberately free of any textbook-specific
// context since this run sends no retrieval/embeddings — pure model quality.
// ---------------------------------------------------------------------------
const QUESTIONS = [
  {
    language: "Malayalam",
    text: "ഫോട്ടോസിന്തസിസ് എന്താണ്? ലളിതമായി വിശദീകരിക്കുക.",
    gloss: "What is photosynthesis? Explain simply.",
  },
  {
    language: "Malayalam",
    text: "ന്യൂട്ടന്റെ ചലനനിയമങ്ങൾ എന്തൊക്കെയാണ്?",
    gloss: "What are Newton's laws of motion?",
  },
  {
    language: "Malayalam",
    text: "ഇന്ത്യൻ സ്വാതന്ത്ര്യസമരത്തിലെ പ്രധാന സംഭവങ്ങൾ ഏതൊക്കെ?",
    gloss: "What are the major events of the Indian independence movement?",
  },
  {
    language: "Malayalam",
    text: "ഒരു സമകോണ ത്രികോണത്തിന്റെ വിസ്തീർണ്ണം എങ്ങനെ കണക്കാക്കാം?",
    gloss: "How do you calculate the area of a right-angled triangle?",
  },
  {
    language: "English",
    text: "Explain the water cycle in simple terms.",
    gloss: null,
  },
  {
    language: "English",
    text: "What is the Pythagorean theorem and how is it used?",
    gloss: null,
  },
  {
    language: "Arabic",
    text: "ما هي أهمية القراءة في حياة الطالب؟",
    gloss: "What is the importance of reading in a student's life?",
  },
  {
    language: "Urdu",
    text: "پانی کا چکر کیا ہے؟ سادہ الفاظ میں بیان کریں۔",
    gloss: "What is the water cycle? Explain in simple words.",
  },
  {
    language: "Sanskrit",
    text: "पञ्चतन्त्रस्य मुख्यः उद्देश्यः कः?",
    gloss: "What is the main purpose of the Panchatantra?",
  },
  {
    language: "Hindi",
    text: "प्रकाश संश्लेषण क्या है? सरल शब्दों में समझाएं।",
    gloss: "What is photosynthesis? Explain in simple words.",
  },
  {
    language: "Hindi",
    text: "भारत के स्वतंत्रता संग्राम की प्रमुख घटनाएं कौन सी हैं?",
    gloss: "What are the major events of India's freedom struggle?",
  },
];

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------
function headers() {
  return {
    Authorization: `Bearer ${provider.apiKey}`,
    "Content-Type": "application/json",
    "HTTP-Referer": "https://razin.hackclub.app",
    "X-OpenRouter-Title": "Right Answer - model quality test",
  };
}

async function askModel(model, question) {
  const start = Date.now();
  try {
    const response = await fetch(`${provider.baseUrl}/chat/completions`, {
      method: "POST",
      headers: headers(),
      body: JSON.stringify({
        model,
        messages: [
          {
            role: "system",
            content:
              "You are a careful school study assistant. Answer directly and clearly in the same language as the question.",
          },
          { role: "user", content: question },
        ],
        temperature: 0.3,
        max_tokens: 700,
      }),
    });
    const elapsedMs = Date.now() - start;
    const body = await response.json().catch(() => null);
    if (!response.ok || !body) {
      return {
        ok: false,
        elapsedMs,
        error: `status=${response.status} body=${JSON.stringify(body)}`,
      };
    }
    const content = body?.choices?.[0]?.message?.content?.trim() ?? "";
    const usage = body?.usage ?? {};
    if (!content) {
      return { ok: false, elapsedMs, error: "empty content" };
    }
    return {
      ok: true,
      elapsedMs,
      content,
      promptTokens: usage.prompt_tokens ?? null,
      completionTokens: usage.completion_tokens ?? null,
    };
  } catch (error) {
    return { ok: false, elapsedMs: Date.now() - start, error: String(error) };
  }
}

function mdEscape(text) {
  return text.replace(/\|/g, "\\|").replace(/\n/g, "<br>");
}

async function main() {
  console.log(`Provider: ${method} (${provider.baseUrl})`);
  console.log(
    `Matrix: ${QUESTIONS.length} questions x 2 families (gemma, qwen) x 2 tiers (fast, reasoning) = ${
      QUESTIONS.length * 4
    } calls\n`
  );

  const results = [];
  let callCount = 0;
  const totalCalls = QUESTIONS.length * 4;

  for (const question of QUESTIONS) {
    const row = { question, answers: {} };
    for (const family of Object.keys(MODELS)) {
      for (const tier of Object.keys(MODELS[family])) {
        const model = MODELS[family][tier];
        callCount += 1;
        process.stdout.write(
          `[${callCount}/${totalCalls}] ${question.language} | ${family}:${tier} (${model})... `
        );
        const result = await askModel(model, question.text);
        row.answers[`${family}:${tier}`] = { model, ...result };
        console.log(
          result.ok
            ? `ok ${result.elapsedMs}ms (${result.completionTokens ?? "?"} tok)`
            : `FAIL ${result.error}`
        );
      }
    }
    results.push(row);
  }

  // ---- Report ----
  const lines = [];
  lines.push("# Model quality comparison — gemma vs qwen, fast vs reasoning");
  lines.push("");
  lines.push(
    `Provider: **${method}** · ${QUESTIONS.length} questions × 4 model/tier combos = ${totalCalls} calls`
  );
  lines.push(
    "No retrieval/embeddings/rerank involved — bare question sent directly to each model. " +
      "This report only collects raw outputs side by side; it does not auto-score quality."
  );
  lines.push("");

  const failures = [];
  for (const row of results) {
    lines.push(`## ${row.question.language}: ${row.question.text}`);
    if (row.question.gloss) {
      lines.push(`*(gloss: ${row.question.gloss})*`);
    }
    lines.push("");
    lines.push("| Model | Latency | Tokens (in/out) | Answer |");
    lines.push("|---|---|---|---|");
    for (const [key, answer] of Object.entries(row.answers)) {
      const [family, tier] = key.split(":");
      const label = `${family} ${tier}<br>\`${answer.model}\``;
      if (!answer.ok) {
        failures.push({ question: row.question, key, error: answer.error });
        lines.push(`| ${label} | ${answer.elapsedMs}ms | — | **FAILED**: ${mdEscape(answer.error)} |`);
      } else {
        lines.push(
          `| ${label} | ${answer.elapsedMs}ms | ${answer.promptTokens ?? "?"}/${answer.completionTokens ?? "?"} | ${mdEscape(answer.content)} |`
        );
      }
    }
    lines.push("");
  }

  lines.push("## Summary");
  lines.push("");
  lines.push(`- Total calls: ${totalCalls}`);
  lines.push(`- Failed: ${failures.length}`);
  if (failures.length > 0) {
    lines.push("");
    lines.push("Failures:");
    for (const failure of failures) {
      lines.push(`- ${failure.question.language} / ${failure.key}: ${failure.error}`);
    }
  }

  writeFileSync(outPath, lines.join("\n"), "utf8");
  console.log(`\nReport written to ${outPath}`);
  if (failures.length > 0) {
    console.error(`${failures.length} call(s) failed — see report for details.`);
    process.exitCode = 1;
  }
}

main();
