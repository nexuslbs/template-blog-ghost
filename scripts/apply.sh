#!/usr/bin/env bash
# Apply the declared theme: download the pinned zip from config/themes.lock.json,
# verify its sha256, upload it with the official Admin API and activate it.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd curl
require_cmd jq
load_env

url="$(stack_url)"
require_creds
theme_name="${GHOST_THEME_NAME:-casper}"
lock="$ROOT_DIR/config/themes.lock.json"

theme_url="$(jq -r --arg n "$theme_name" '.themes[] | select(.name==$n) | .url' "$lock")"
[ -n "$theme_url" ] && [ "$theme_url" != "null" ] || die "no theme '$theme_name' in $lock"
expected_sha="$(jq -r --arg n "$theme_name" '.themes[] | select(.name==$n) | .sha256 // empty' "$lock")"

mkdir -p "$RUNTIME_DIR"
zip="$RUNTIME_DIR/$(basename "$theme_url")"
if [ ! -f "$zip" ]; then
  log "downloading theme $theme_name from $theme_url"
  curl -fsSL "$theme_url" -o "$zip"
fi
if [ -n "$expected_sha" ]; then
  actual_sha="$(sha256sum "$zip" | awk '{print $1}')"
  [ "$actual_sha" = "$expected_sha" ] \
    || die "sha256 mismatch for $zip: got $actual_sha, expected $expected_sha"
  log "sha256 verified: $actual_sha"
fi

kid="$(admin_key_id)"; secret="$(admin_key_secret)"

log "uploading theme: POST $url/ghost/api/admin/themes/upload/"
token="$(make_jwt "$kid" "$secret")"
curl -fsS -X POST "$url/ghost/api/admin/themes/upload/" \
  -H "Authorization: Ghost $kid:$token" \
  -H 'Accept-Version: v6.0' \
  -F "file=@$zip" \
  | jq '{themes: [.themes[].name]}'

log "activating theme: PUT $url/ghost/api/admin/themes/$theme_name/activate/"
token="$(make_jwt "$kid" "$secret")"
curl -fsS -X PUT "$url/ghost/api/admin/themes/$theme_name/activate/" \
  -H "Authorization: Ghost $kid:$token" \
  -H 'Accept-Version: v6.0' \
  | jq '{active: [.themes[] | select(.active==true) | .name]}'

log "apply: OK"
