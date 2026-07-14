#!/usr/bin/env bash
set -euo pipefail

WORKDIR="${RIGHT_ANSWER_WORKDIR:-/content/rightanswer-2}"
ARCHIVE_NAME="${1:-right-answer-storage.zip}"

cd "${WORKDIR}"
rm -f "${ARCHIVE_NAME}"
zip -r "${ARCHIVE_NAME}" storage
echo "${WORKDIR}/${ARCHIVE_NAME}"
