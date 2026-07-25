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
#
# Build api and web SEQUENTIALLY, not `$COMPOSE build` (which builds every
# service concurrently) — this VPS only has 2GB RAM, and a concurrent
# rustc compile + pnpm install has OOM-killed the build mid-way more than
# once (previously api's own build alone under parallel codegen units,
# see apps/api/Dockerfile's --jobs 1; this time web's pnpm install got
# killed while api was building at the same time). One service finishing
# before the next starts keeps peak memory bounded to whichever single
# build is running.
$COMPOSE build api
$COMPOSE build web
$COMPOSE up -d postgres redis qdrant
$COMPOSE up -d api web
$COMPOSE ps

bash deploy/scripts/clean.sh

echo "Run this after your textbook embeddings exist in Postgres:"
echo "$COMPOSE run --rm api migrate_qdrant"
