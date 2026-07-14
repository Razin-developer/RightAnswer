#!/usr/bin/env bash
set -euo pipefail

WORKDIR="${RIGHT_ANSWER_WORKDIR:-/content/rightanswer-2}"
CSV_PATH="${1:-ingest.csv}"
VERSION_PREFIX="${2:-colab-qwen4b-$(date +%Y%m%d-%H%M%S)}"
PARALLEL="${RIGHT_ANSWER_BATCH_PARALLEL:-1}"
CHAPTER_WORKERS="${RIGHT_ANSWER_CHAPTER_WORKERS:-8}"
OCR_WORKERS="${RIGHT_ANSWER_OCR_WORKERS:-8}"
ATTEMPTS="${RIGHT_ANSWER_BATCH_ATTEMPTS:-3}"

cd "${WORKDIR}"
source .venv-qwen-embeddings/bin/activate

pnpm textbook:batch-csv -- \
  --csv "${CSV_PATH}" \
  --version-prefix "${VERSION_PREFIX}" \
  --fresh \
  --parallel "${PARALLEL}" \
  --chapter-workers "${CHAPTER_WORKERS}" \
  --ocr-workers "${OCR_WORKERS}" \
  --attempts "${ATTEMPTS}"
