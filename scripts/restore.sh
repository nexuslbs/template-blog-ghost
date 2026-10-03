#!/usr/bin/env bash
# Restore a backup produced by scripts/backup.sh.
#   usage: restore.sh <backup-dir | newest>
# Ghost is stopped while the database and content are restored, then started
# again; Ghost runs its own migrations on boot.
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

log "restoring from $dir"
log "stopping ghost (writes pause while state is replaced)"
compose stop ghost

log "1/2 restoring database"
compose exec -T db sh -c \
  'exec mysql -uroot -p"$(cat /run/secrets/ghost_db_secret)" ghost' < "$dir/ghost.sql"

log "2/2 restoring content"
compose exec -T ghost sh -c 'tar xzf - -C /var/lib/ghost/content' < "$dir/content.tar.gz"

log "starting ghost"
compose start ghost
wait_for_healthy ghost 90 || die "ghost did not become healthy after restore"
compose ps
log "restore: OK"
