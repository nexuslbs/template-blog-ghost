#!/usr/bin/env bash
# Restore a backup produced by scripts/backup.sh.
#   usage: restore.sh <backup-dir | newest>
# The db service must be up before the dump can be imported, so this script
# brings db up and waits for its healthcheck first. That makes restore work both
# after `down` (volumes kept) and on a fresh `up` over empty volumes. Ghost is
# stopped while the database and content are restored, then started again;
# Ghost runs its own migrations on boot.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd docker
load_env

arg="${1:-newest}"
if [ "$arg" = "newest" ]; then
  dir="$(ls -1d "$ROOT_DIR"/backups/*/ 2>/dev/null | sort | tail -n1 || true)"
  [ -n "$dir" ] || die "no backup directories under $ROOT_DIR/backups"
else
  dir="$arg"
fi
dir="${dir%/}"

[ -f "$dir/ghost.sql" ] || die "missing $dir/ghost.sql"
[ -f "$dir/content.tar.gz" ] || die "missing $dir/content.tar.gz"

log "ensuring db is up and healthy (restore needs a running database)"
compose up -d db
wait_for_healthy db 60 || { compose logs --tail=50 db; die "db did not become healthy"; }

log "restoring from $dir"
log "stopping ghost (writes pause while state is replaced)"
compose stop ghost

log "1/2 restoring database"
compose exec -T db sh -c \
  'exec mysql -uroot -p"$(cat /run/secrets/ghost_db_secret)" ghost' < "$dir/ghost.sql"

log "2/2 restoring content"
# ghost is stopped here, so a one-off container with the same volume and
# entrypoint tar is used instead of 'exec' (which needs a running service).
compose run --rm --no-deps --entrypoint tar -T ghost xzf - -C /var/lib/ghost/content < "$dir/content.tar.gz"

log "starting ghost"
compose up -d ghost
wait_for_healthy ghost 120 || die "ghost did not become healthy after restore"
compose ps
log "restore: OK"
