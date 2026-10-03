#!/usr/bin/env bash
# Non-interactive, browser-free bootstrap through the official Admin API:
#   1) health: GET  /ghost/api/admin/site/
#   2) setup:  POST /ghost/api/admin/authentication/setup/   (unauth, once)
#   3) session POST /ghost/api/admin/session/  (Origin header; owner login)
#   4) integration POST /ghost/api/admin/integrations/?include=api_keys
# The Admin API id/secret are written to runtime/admin-api.json (mode 600,
# gitignored). No secret value is printed; the response shows the key id and a
# redacted secret prefix.
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
body_file="$(mktemp)"
trap 'rm -f "$cookie_jar" "$body_file"' EXIT

log "1/4 site health: GET $url/ghost/api/admin/site/"
code="$(curl -sS -o /dev/null -w '%{http_code}' "$url/ghost/api/admin/site/")"
log "site health: HTTP $code"
[ "$code" = "200" ] || die "site health returned HTTP $code"

setup_status="$(curl -fsS "$url/ghost/api/admin/authentication/setup/" | jq -r '.setup[0].status')"
if [ "$setup_status" != "true" ]; then
  log "2/4 setup owner (unauthenticated, accepted only before setup)"
  code="$(curl -sS -o "$body_file" -w '%{http_code}' -X POST \
    "$url/ghost/api/admin/authentication/setup/" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg n "$admin_name" --arg e "$admin_email" \
                --arg p "$admin_password" --arg t "$blog_title" \
                '{setup:[{name:$n,email:$e,"password":$p,blogTitle:$t}]}')")"
  log "setup: HTTP $code"
  [ "$code" = "201" ] || { cat "$body_file"; die "setup returned HTTP $code"; }
else
  log "2/4 setup already complete, skipping"
fi

log "3/4 owner session: POST $url/ghost/api/admin/session/"
code="$(curl -sS -o "$body_file" -w '%{http_code}' -X POST \
  "$url/ghost/api/admin/session/" \
  -H 'Content-Type: application/json' \
  -H "Origin: $url" \
  -c "$cookie_jar" \
  -d "$(jq -nc --arg u "$admin_email" --arg p "$admin_password" \
              '{username:$u,"password":$p}')")"
log "session: HTTP $code (cookie stored)"
[ "$code" = "201" ] || { cat "$body_file"; die "session returned HTTP $code"; }

log "4/4 integration + api keys: POST $url/ghost/api/admin/integrations/?include=api_keys"
code="$(curl -sS -o "$body_file" -w '%{http_code}' -X POST \
  "$url/ghost/api/admin/integrations/?include=api_keys" \
  -H 'Content-Type: application/json' \
  -H "Origin: $url" \
  -H 'Accept-Version: v6.0' \
  -b "$cookie_jar" \
  -d "$(jq -nc --arg n "$integration_name" '{integrations:[{name:$n}]}')")"
log "integration: HTTP $code"
resp="$(cat "$body_file")"
[ "$code" = "201" ] || { printf '%s\n' "$resp"; die "integration returned HTTP $code"; }

# Print keys with the secret REDACTED (id + first 6 chars only). The full JSON
# goes only to the gitignored runtime file.
printf '%s\n' "$resp" | jq '{integration: .integrations[0].name,
  keys: [.integrations[0].api_keys[] | {type, id, secret: ((.secret[0:6]) + "...REDACTED")}]}'

umask 077
printf '%s\n' "$resp" | jq '.integrations[0]' > "$creds_file"
chmod 600 "$creds_file"
log "wrote $creds_file (mode 600, gitignored)"
log "bootstrap: OK"
