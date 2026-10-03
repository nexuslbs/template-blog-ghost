#!/usr/bin/env bash
# Backup the two stateful pieces, exactly as docs.ghost.org/faq/manual-backup
# prescribes:
#   - mysqldump of the `ghost` database from the db container
#   - tar of the whole /var/lib/ghost/content tree from the ghost container
# Difference from the docs snippet: this stack supplies the password via the
# *_FILE secret, so the command reads it from /run/secrets inside the container
# instead of $MYSQL_ROOT_PASSWORD.
# Output lands in backups/<UTC timestamp>/ (gitignored).
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd docker
load_env

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
dir="$ROOT_DIR/backups/$stamp"
mkdir -p "$dir"

log "1/2 mysqldump -> $dir/ghost.sql"
compose exec -T db sh -c \
  'exec mysqldump --no-tablespaces -uroot -p"$(cat /run/secrets/ghost_db_secret)" ghost' \
  > "$dir/ghost.sql"

log "2/2 content tar -> $dir/content.tar.gz"
compose exec -T ghost tar czf - -C /var/lib/ghost/content . > "$dir/content.tar.gz"

( cd "$dir" && sha256sum ghost.sql content.tar.gz > SHA256SUMS )
log "wrote $(du -h "$dir" | awk '{print $1}') to $dir"
ls -l "$dir"
log "backup: OK"
