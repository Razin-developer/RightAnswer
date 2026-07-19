#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${1:-https://github.com/Razin-developer/rightanswer-2.git}"
WORKDIR="${RIGHT_ANSWER_WORKDIR:-/content/rightanswer-2}"
BRANCH="${RIGHT_ANSWER_GIT_BRANCH:-main}"

rm -rf "${WORKDIR}"
git clone --branch "${BRANCH}" "${REPO_URL}" "${WORKDIR}"
cd "${WORKDIR}"

python3 -m pip install --upgrade pip wheel setuptools

if ! command -v pnpm >/dev/null 2>&1; then
  curl -fsSL https://get.pnpm.io/install.sh | sh -
  export PNPM_HOME="/root/.local/share/pnpm"
  export PATH="${PNPM_HOME}:${PATH}"
fi

corepack enable
corepack prepare pnpm@11.7.0 --activate

pnpm install

python3 -m venv .venv-qwen-embeddings
source .venv-qwen-embeddings/bin/activate
pip install -r apps/api/python/requirements-qwen-embeddings.txt

cat > .env <<EOF
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/right_answer
REDIS_URL=
JWT_SECRET=right-answer-colab-secret
NEXT_PUBLIC_API_URL=http://localhost:4000/api/v1
GROQ_API_KEY=
GEMINI_API_KEY=
OPENAI_API_KEY=
RIGHT_ANSWER_EMBEDDING_BACKEND=hf-transformers
RIGHT_ANSWER_EMBEDDING_MODEL=${RIGHT_ANSWER_EMBEDDING_MODEL:-perplexity-ai/pplx-embed-v1-0.6b}
RIGHT_ANSWER_EMBEDDING_DIMENSIONS=${RIGHT_ANSWER_EMBEDDING_DIMENSIONS:-1024}
RIGHT_ANSWER_EMBEDDING_MAX_LENGTH=${RIGHT_ANSWER_EMBEDDING_MAX_LENGTH:-512}
RIGHT_ANSWER_EMBEDDING_BATCH_SIZE=${RIGHT_ANSWER_EMBEDDING_BATCH_SIZE:-96}
RIGHT_ANSWER_EMBEDDING_THREADS=${RIGHT_ANSWER_EMBEDDING_THREADS:-2}
RIGHT_ANSWER_EMBEDDING_MAX_REQUESTS_PER_WORKER=${RIGHT_ANSWER_EMBEDDING_MAX_REQUESTS_PER_WORKER:-8}
RIGHT_ANSWER_EMBEDDING_ALLOW_FALLBACK=0
RIGHT_ANSWER_EMBEDDING_DEVICE=${RIGHT_ANSWER_EMBEDDING_DEVICE:-cuda}
RIGHT_ANSWER_QUERY_INSTRUCTION=
EOF

pnpm db:generate

mkdir -p storage/logs
nohup node scripts/start-local-postgres.mjs > storage/logs/local-postgres.log 2>&1 &

for attempt in $(seq 1 60); do
  if node scripts/check-db.mjs >/tmp/right-answer-db-check.json 2>/tmp/right-answer-db-check.err; then
    cat /tmp/right-answer-db-check.json
    exit 0
  fi
  sleep 2
done

cat /tmp/right-answer-db-check.err || true
echo "Local PostgreSQL did not become ready in time." >&2
exit 1
