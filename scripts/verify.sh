#!/usr/bin/env bash
# End-to-end verification: health, DB, setup state, active theme, and a real
# publish through the official Admin API whose PUBLIC url must answer 200.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd curl
require_cmd jq
load_env
url="$(stack_url)"

log "1. site health: GET $url/ghost/api/admin/site/"
curl -fsS "$url/ghost/api/admin/site/" | jq '{title: .site.title, version: .site.version, url: .site.url}'

log "2. database ping"
compose exec -T db sh -c 'mysqladmin ping --silent -h 127.0.0.1 -uroot -p"$(cat /run/secrets/ghost_db_secret)"'
log "db: OK"

log "3. setup status"
curl -fsS "$url/ghost/api/admin/authentication/setup/" | jq .

# The themes LIST endpoint is Owner-only and refuses integration tokens (403),
# so the active theme is read from the response of the (idempotent) activate
# call, which the integration token may make.
log "4. active theme via idempotent activate (integrations may not list themes)"
require_creds
kid="$(admin_key_id)"; secret="$(admin_key_secret)"
lock="$ROOT_DIR/config/themes.lock.json"
theme_name="${GHOST_THEME_NAME:-casper}"
install_as="$(jq -r --arg n "$theme_name" '.themes[] | select(.name==$n) | (.installAs // .name)' "$lock")"
body="$(mktemp)"
trap 'rm -f "$body"' EXIT
token="$(make_jwt "$kid" "$secret")"
code="$(curl -sS -o "$body" -w '%{http_code}' -X PUT \
  "$url/ghost/api/admin/themes/$install_as/activate/" \
  -H "Authorization: Ghost $token" -H 'Accept-Version: v6.0')"
log "activate $install_as: HTTP $code"
jq '{active: [.themes[] | select(.active==true) | .name]}' "$body" 2>/dev/null || cat "$body"
[ "$code" = "200" ] || die "theme activate returned HTTP $code"

log "5. publish smoke post: POST $url/ghost/api/admin/posts/?source=html"
post_title="Template smoke $(date -u +%Y-%m-%dT%H:%M:%SZ)"
token="$(make_jwt "$kid" "$secret")"
resp="$(curl -fsS -X POST "$url/ghost/api/admin/posts/?source=html" \
  -H "Authorization: Ghost $token" \
  -H 'Accept-Version: v6.0' \
  -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg t "$post_title" \
    '{posts:[{title:$t,html:"<p>Template smoke post.</p>",status:"published"}]}')")"
public_url="$(printf '%s' "$resp" | jq -r '.posts[0].url')"
printf 'posts[0].url = %s\n' "$public_url"

code="$(curl -sS -o /dev/null -w '%{http_code}' "$public_url")"
printf 'GET %s -> HTTP %s\n' "$public_url" "$code"
[ "$code" = "200" ] || die "public post did not return HTTP 200 (got $code)"

log "verify: OK"
