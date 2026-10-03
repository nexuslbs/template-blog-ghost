#!/usr/bin/env bash
# Non-interactive, browser-free bootstrap through the official Admin API:
#   1) health: GET  /ghost/api/admin/site/
#   2) setup:  POST /ghost/api/admin/authentication/setup/   (unauth, once)
#   3) session POST /ghost/api/admin/session/  (Origin header; owner login)
#   4) integration POST /ghost/api/admin/integrations/?include=api_keys
# The Admin API id/secret are written to runtime/admin-api.json (mode 600,
# gitignored). Nothing secret is printed.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd curl
require_cmd jq
load_env

url="$(stack_url)"
admin_name="${GHOST_ADMIN_NAME:-Owner}"
admin_email="${GHOST_ADMIN_EMAIL:?set GHOST_ADMIN_EMAIL in .env}"
admin_password="${GHOST_ADMIN_PASSWORD:?set GHOST_ADMIN_PASSWORD in .env}"
blog_title="${GHOST_BLOG_TITLE:-Ghost}"
integration_name="${GHOST_INTEGRATION_NAME:-dsh-template}"

mkdir -p "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"
creds_file="$RUNTIME_DIR/admin-api.json"
cookie_jar="$(mktemp)"
trap 'rm -f "$cookie_jar"' EXIT

log "1/4 site health: GET $url/ghost/api/admin/site/"
curl -fsS "$url/ghost/api/admin/site/" -o /dev/null && log "site: OK"

setup_status="$(curl -fsS "$url/ghost/api/admin/authentication/setup/" | jq -r '.setup[0].status')"
if [ "$setup_status" != "true" ]; then
  log "2/4 setup owner (unauthenticated, only before setup)"
  curl -fsS -X POST "$url/ghost/api/admin/authentication/setup/" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg n "$admin_name" --arg e "$admin_email" \
                --arg p "$admin_password" --arg t "$blog_title" \
                '{setup:[{name:$n,email:$e,"password":$p,blogTitle:$t}]}')" \
    -o /dev/null
  log "setup: 201"
else
  log "2/4 setup already complete, skipping"
fi

log "3/4 owner session: POST $url/ghost/api/admin/session/"
curl -fsS -X POST "$url/ghost/api/admin/session/" \
  -H 'Content-Type: application/json' \
  -H "Origin: $url" \
  -c "$cookie_jar" \
  -d "$(jq -nc --arg u "$admin_email" --arg p "$admin_password" \
              '{username:$u,"password":$p}')" \
  -o /dev/null
log "session: 201 (cookie stored)"

log "4/4 integration + api keys: POST $url/ghost/api/admin/integrations/?include=api_keys"
resp="$(curl -fsS -X POST "$url/ghost/api/admin/integrations/?include=api_keys" \
  -H 'Content-Type: application/json' \
  -H "Origin: $url" \
  -H 'Accept-Version: v6.0' \
  -b "$cookie_jar" \
  -d "$(jq -nc --arg n "$integration_name" '{integrations:[{name:$n}]}')")"

# Print keys with the secret REDACTED. The full JSON goes only to the
# gitignored runtime file.
printf '%s\n' "$resp" | jq '{integration: .integrations[0].name,
  keys: [.integrations[0].api_keys[] | {type, id, secret: ((.secret[0:6]) + "...REDACTED")}]}'

umask 077
printf '%s\n' "$resp" | jq '.integrations[0]' > "$creds_file"
chmod 600 "$creds_file"
log "wrote $creds_file (mode 600, gitignored)"
log "bootstrap: OK"
