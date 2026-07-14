#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${1:-https://github.com/Razin-developer/rightanswer-2.git}"
CSV_PATH="${2:-ingest.csv}"
VERSION_PREFIX="${3:-colab-qwen4b-$(date +%Y%m%d-%H%M%S)}"
ARCHIVE_NAME="${4:-right-answer-storage.zip}"

bash scripts/colab/bootstrap-right-answer.sh "${REPO_URL}"
bash scripts/colab/run-right-answer-batch.sh "${CSV_PATH}" "${VERSION_PREFIX}"
bash scripts/colab/zip-storage.sh "${ARCHIVE_NAME}"
