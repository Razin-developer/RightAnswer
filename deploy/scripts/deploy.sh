#!/usr/bin/env bash
set -euo pipefail

COMPOSE="docker compose --env-file .env.production -f docker-compose.prod.yml"

if [[ ! -f .env.production ]]; then
  echo "Missing .env.production. Copy .env.production.example and fill real secrets first."
  exit 1
fi

git pull --ff-only
git lfs pull --include="storage/**"
$COMPOSE build
$COMPOSE up -d postgres redis qdrant
$COMPOSE up -d api web
$COMPOSE ps

echo "Run this after your textbook embeddings exist in Postgres:"
echo "$COMPOSE run --rm api migrate_qdrant"
