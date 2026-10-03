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

log "4. active theme (Admin API)"
require_creds
kid="$(admin_key_id)"; secret="$(admin_key_secret)"
token="$(make_jwt "$kid" "$secret")"
curl -fsS "$url/ghost/api/admin/themes/" \
  -H "Authorization: Ghost $kid:$token" -H 'Accept-Version: v6.0' \
  | jq '{active: [.themes[] | select(.active==true) | .name]}'

log "5. publish smoke post: POST $url/ghost/api/admin/posts/?source=html"
post_title="Template smoke $(date -u +%Y-%m-%dT%H:%M:%SZ)"
token="$(make_jwt "$kid" "$secret")"
resp="$(curl -fsS -X POST "$url/ghost/api/admin/posts/?source=html" \
  -H "Authorization: Ghost $kid:$token" \
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
