#!/usr/bin/env bash
# Apply pending database migrations.
#
# Ghost has its own migrator: on container start boot.js ->
# DatabaseStateManager.makeReady() runs every pending knex migration. There is
# no separate official "migrate" command for this image (Docker Hub warns that
# most Ghost-CLI commands do not work in the container), so the official route
# is exactly: ensure db is healthy, then (re)start ghost and let it migrate.
#
# Upgrades: change the pinned tag in docker-compose.yml, run this script, then
# verify. Rollback: restore the pre-upgrade dump, pin the previous tag, run this
# script again.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd docker
load_env

log "ensuring db is healthy"
compose up -d db
wait_for_healthy db 60 || { compose logs --tail=50 db; die "db did not become healthy"; }

log "recreating ghost so boot.js runs pending migrations"
compose up -d --force-recreate ghost
wait_for_healthy ghost 120 || { compose logs --tail=100 ghost; die "ghost did not become healthy"; }

log "database schema version"
compose exec -T db sh -c \
  'exec mysql -N -B -uroot -p"$(cat /run/secrets/ghost_db_secret)" ghost' <<'SQL'
SELECT value FROM settings WHERE `key`='databaseVersion';
SQL

compose ps
log "migrate: OK"
