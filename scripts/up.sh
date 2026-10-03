#!/usr/bin/env bash
# Bring the Ghost stack up and wait until BOTH services report healthy.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd docker
load_env

secret_file="${MYSQL_ROOT_PASSWORD_FILE:-./secrets/mysql_root_password.txt}"
case "$secret_file" in
  /*) : ;;
  *) secret_file="$ROOT_DIR/${secret_file#./}" ;;
esac
if [ ! -s "$secret_file" ]; then
  die "secret file missing or empty: $secret_file
create it with:
  mkdir -p \"$(dirname "$secret_file")\" && openssl rand -base64 24 > \"$secret_file\""
fi
# The compose file secret preserves the host file mode inside the container;
# Ghost runs as the unprivileged `node` user, so the file must be readable by
# it. Keep the parent directory private (0700) and the file read-only (0444).
chmod 700 "$(dirname "$secret_file")" 2>/dev/null || true
chmod 0444 "$secret_file" 2>/dev/null || true

log "starting stack (project ${COMPOSE_PROJECT_NAME:-template-blog-ghost})"
compose up -d

log "waiting for db to become healthy"
wait_for_healthy db 60 || { compose logs --tail=50 db; die "db did not become healthy"; }

log "waiting for ghost to become healthy (first boot runs DB migrations)"
wait_for_healthy ghost 90 || { compose logs --tail=100 ghost; die "ghost did not become healthy"; }

compose ps
log "up: OK"
