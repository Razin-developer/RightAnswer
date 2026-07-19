#!/usr/bin/env bash
set -euo pipefail

COMPOSE="docker compose --env-file .env.production -f docker-compose.prod.yml"

$COMPOSE ps
curl -fsS http://127.0.0.1:4000/health
echo
curl -fsS http://127.0.0.1:3000 >/dev/null
echo "Local web/API checks passed."
