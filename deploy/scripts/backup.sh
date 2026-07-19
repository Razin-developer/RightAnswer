#!/usr/bin/env bash
set -euo pipefail

COMPOSE="docker compose --env-file .env.production -f docker-compose.prod.yml"
BACKUP_DIR="${BACKUP_DIR:-$PWD/backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"

if [[ -f .env.production ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env.production
  set +a
fi

mkdir -p "${BACKUP_DIR}"

$COMPOSE exec -T postgres pg_dump -U "${POSTGRES_USER:-right_answer}" "${POSTGRES_DB:-right_answer}" \
  | gzip > "${BACKUP_DIR}/postgres-${STAMP}.sql.gz"

docker run --rm \
  -v right-answer_qdrant_data:/qdrant-data:ro \
  -v "${BACKUP_DIR}:/backup" \
  alpine tar -czf "/backup/qdrant-${STAMP}.tar.gz" -C /qdrant-data .

echo "Backups written to ${BACKUP_DIR}"
