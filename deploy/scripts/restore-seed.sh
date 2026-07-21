#!/usr/bin/env bash
set -euo pipefail

COMPOSE="docker compose --env-file .env.production -f docker-compose.prod.yml"
SEED_SQL="${SEED_SQL:-storage/seeds/postgres-textbook-seed.sql}"
QDRANT_SEED="${QDRANT_SEED:-storage/seeds/qdrant-right-answer-v1.18.3.tar.gz}"

if [[ ! -f "${SEED_SQL}" ]]; then
  # clean.sh removes storage/seeds after a successful deploy to save disk —
  # pull it back from git-lfs on demand rather than requiring it to always
  # be present on disk.
  echo "${SEED_SQL} not on disk, pulling from git-lfs..."
  git lfs pull --include="storage/seeds/**"
fi

if [[ ! -f "${SEED_SQL}" ]]; then
  echo "Missing ${SEED_SQL}. Run scripts/export-postgres-seed.mjs locally and push the seed first."
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env.production
set +a

$COMPOSE up -d postgres redis qdrant

echo "[restore] waiting for PostgreSQL"
for _ in {1..60}; do
  if $COMPOSE exec -T postgres pg_isready \
    -U "${POSTGRES_USER:-right_answer}" \
    -d "${POSTGRES_DB:-right_answer}" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

$COMPOSE exec -T postgres pg_isready \
  -U "${POSTGRES_USER:-right_answer}" \
  -d "${POSTGRES_DB:-right_answer}"

echo "[restore] loading PostgreSQL textbook seed"
$COMPOSE exec -T postgres psql \
  -v ON_ERROR_STOP=1 \
  -U "${POSTGRES_USER:-right_answer}" \
  -d "${POSTGRES_DB:-right_answer}" < "${SEED_SQL}"

if [[ -f "${QDRANT_SEED}" ]]; then
  echo "[restore] restoring Qdrant seed archive"
  $COMPOSE stop qdrant
  docker run --rm \
    -v right-answer_qdrant_data:/qdrant-data \
    -v "$PWD/storage/seeds:/seed:ro" \
    alpine sh -lc "rm -rf /qdrant-data/* && tar -xzf /seed/$(basename "${QDRANT_SEED}") -C /qdrant-data"
  $COMPOSE up -d qdrant
else
  echo "[restore] no Qdrant seed archive found; rebuilding Qdrant from PostgreSQL"
  $COMPOSE run --rm api migrate_qdrant
fi

echo "[restore] seed restore complete"
