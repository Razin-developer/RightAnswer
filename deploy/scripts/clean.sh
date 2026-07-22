#!/usr/bin/env bash
set -euo pipefail

# Reclaims disk space on the VPS after a deploy. Safe to run any time and
# any number of times — everything removed here is either reproducible
# (docker build cache, rebuilt on next `docker compose build`) or already
# loaded into Postgres/Qdrant and recoverable from git-lfs if ever needed
# again (via `git lfs pull --include=...`, see restore-seed.sh).
#
# What's NOT touched: .env.production, docker volumes (postgres/qdrant/redis
# data), docker-compose*.yml, apps/api, apps/web sources needed to rebuild
# images.

cd "$(dirname "$0")/../.."

echo "[clean] before:"
df -h / | tail -1

# Never built or run on this server: mobile builds happen in GitHub
# Actions (apps/app), and both of these are superseded/undeployed
# (apps/api-node-legacy predates the Rust API migration; apps/web-next-legacy
# predates the current apps/web). `docker compose build` never reads them.
for dir in apps/app apps/api-node-legacy apps/web-next-legacy; do
  if [[ -d "$dir" ]]; then
    size=$(du -sh "$dir" 2>/dev/null | cut -f1)
    rm -rf "$dir"
    echo "[clean] removed $dir ($size)"
  fi
done

# storage/imports (raw source PDFs) is git-lfs content only needed during
# the one-time ingestion run that already happened — the resulting
# embeddings/text live in Postgres and Qdrant, which is what the running app
# actually reads for generation. storage/seeds is a one-time restore
# input, pulled back on demand by restore-seed.sh if needed again.
#
# storage/textbooks is deliberately NOT cleaned here: nginx serves it live
# at /textbook-assets/ (see deploy/nginx/rightanswer.conf) for the app's
# sources drawer (page illustrations/diagrams/tables) — deleting it would
# break real, in-use image URLs, not just reclaim dead weight.
for dir in storage/imports storage/seeds; do
  if [[ -d "$dir" ]]; then
    size=$(du -sh "$dir" 2>/dev/null | cut -f1)
    rm -rf "${dir:?}"/*
    echo "[clean] removed $dir contents ($size)"
  fi
done

# API error/panic logs (see apps/api/src/main.rs — one file per day,
# never auto-deleted by the writer itself). Keep 14 days for post-incident
# review, drop anything older.
if [[ -d logs/api ]]; then
  find logs/api -name '*.log*' -mtime +14 -delete
  echo "[clean] pruned api logs older than 14 days"
fi

# Reclaim finished docker build layers — every `docker compose build` only
# needs the latest layer chain, not the full history of every past build.
docker builder prune -f >/dev/null
echo "[clean] pruned docker build cache"

# Dangling (untagged, unused) images from old builds.
docker image prune -f >/dev/null
echo "[clean] pruned dangling docker images"

echo "[clean] after:"
df -h / | tail -1
