#!/usr/bin/env bash
# Runs on the Guis VPS via the deploy-vps GitHub Actions workflow.
set -euo pipefail

cd "$HOME/guis"
test "$(git branch --show-current)" = main || {
  echo 'The VPS checkout must be on main' >&2
  exit 1
}
test -z "$(git status --porcelain)" || {
  echo 'The VPS checkout has local changes' >&2
  exit 1
}

echo 'Backing up the production database'
docker compose exec -T backup sh -c '
  file="/backups/guis-before-deploy-$(date -u +%Y%m%dT%H%M%S).dump"
  pg_dump -Fc -f "$file"
  test -s "$file"
' </dev/null

echo 'Updating the VPS checkout'
git pull --ff-only origin main </dev/null

echo 'Rebuilding and checking the stack'
docker compose up -d --build --wait --wait-timeout 180 </dev/null
docker compose ps --format 'table {{.Service}}\t{{.Status}}' </dev/null
echo DEPLOYMENT_COMPLETE
