#!/usr/bin/env bash
set -euo pipefail

COMPOSE="docker compose --env-file .env.production -f docker-compose.prod.yml"

if [[ ! -f .env.production ]]; then
  echo "Missing .env.production. Copy .env.production.example and fill real secrets first."
  exit 1
fi

# .env.production holds live DB/JWT secrets; keep it owner-read/write only
# regardless of the umask the file happened to be created with.
chmod 600 .env.production

git pull --ff-only
# storage/** (source PDFs, processed page images, seed dumps) is only
# needed for the one-off ingestion/restore-seed flow, not for running the
# app — deliberately not pulled here. Run restore-seed.sh directly (it
# pulls what it needs from git-lfs on demand) if you need to reload seed
# data on this host.
$COMPOSE build
$COMPOSE up -d postgres redis qdrant
$COMPOSE up -d api web
$COMPOSE ps

bash deploy/scripts/clean.sh

echo "Run this after your textbook embeddings exist in Postgres:"
echo "$COMPOSE run --rm api migrate_qdrant"
