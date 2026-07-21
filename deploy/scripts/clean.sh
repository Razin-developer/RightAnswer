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
# images. apps/app (Flutter) is git-tracked source only — nothing on this
# server ever builds or runs it (mobile builds happen in GitHub Actions),
# but it's a few MB of Dart source, not worth special-casing here; this
# script focuses on the things that actually matter for disk space.

cd "$(dirname "$0")/../.."

echo "[clean] before:"
df -h / | tail -1

# storage/textbooks (processed page images) and storage/imports (raw source
# PDFs) are git-lfs content only needed during the one-time ingestion run
# that already happened — the resulting embeddings/text live in Postgres
# and Qdrant, which is what the running app actually reads. Nothing on this
# server currently serves these image files over HTTP.
for dir in storage/textbooks storage/imports storage/seeds; do
  if [[ -d "$dir" ]]; then
    size=$(du -sh "$dir" 2>/dev/null | cut -f1)
    rm -rf "${dir:?}"/*
    echo "[clean] removed $dir contents ($size)"
  fi
done

# Reclaim finished docker build layers — every `docker compose build` only
# needs the latest layer chain, not the full history of every past build.
docker builder prune -f >/dev/null
echo "[clean] pruned docker build cache"

# Dangling (untagged, unused) images from old builds.
docker image prune -f >/dev/null
echo "[clean] pruned dangling docker images"

echo "[clean] after:"
df -h / | tail -1
