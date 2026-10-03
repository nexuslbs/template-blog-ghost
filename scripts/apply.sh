#!/usr/bin/env bash
# Apply the declared theme: download the pinned zip from config/themes.lock.json,
# verify its sha256, repack it without symlink entries (Ghost rejects those with
# SYMLINK_NOT_ALLOWED), then upload and activate it through the official Admin
# API.
#
# Ghost names an uploaded theme after the uploaded ZIP FILE and refuses to
# override its bundled default theme, so the lock's `installAs` name is used for
# the zip filename and the activate path.
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd curl
require_cmd jq
require_cmd unzip
require_cmd zip
load_env

url="$(stack_url)"
require_creds
theme_name="${GHOST_THEME_NAME:-casper}"
lock="$ROOT_DIR/config/themes.lock.json"

theme_url="$(jq -r --arg n "$theme_name" '.themes[] | select(.name==$n) | .url' "$lock")"
[ -n "$theme_url" ] && [ "$theme_url" != "null" ] || die "no theme '$theme_name' in $lock"
theme_version="$(jq -r --arg n "$theme_name" '.themes[] | select(.name==$n) | .version' "$lock")"
install_as="$(jq -r --arg n "$theme_name" '.themes[] | select(.name==$n) | (.installAs // .name)' "$lock")"
expected_sha="$(jq -r --arg n "$theme_name" '.themes[] | select(.name==$n) | .sha256 // empty' "$lock")"

mkdir -p "$RUNTIME_DIR"
zip="$RUNTIME_DIR/$(basename "$theme_url")"
if [ ! -f "$zip" ]; then
  log "downloading theme $theme_name $theme_version from $theme_url"
  curl -fsSL "$theme_url" -o "$zip"
fi
if [ -n "$expected_sha" ]; then
  actual_sha="$(sha256sum "$zip" | awk '{print $1}')"
  [ "$actual_sha" = "$expected_sha" ] \
    || die "sha256 mismatch for $zip: got $actual_sha, expected $expected_sha"
  log "sha256 verified: $actual_sha"
fi

# Ghost 6.67 refuses any zip with a symlink entry. The upstream Casper release
# zip contains one (CLAUDE.md -> AGENTS.md), so the archive is unpacked and
# repacked with every link dereferenced (cp -rL) before upload.
upload_zip="$RUNTIME_DIR/${install_as}.zip"
work="$(mktemp -d)"; deref="$(mktemp -d)"; body="$(mktemp)"
trap 'rm -rf "$work" "$deref" "$body"' EXIT
unzip -q "$zip" -d "$work"
cp -rL "$work"/. "$deref"/
rm -f "$upload_zip"
( cd "$deref" && zip -q -r -X "$upload_zip" . )
if unzip -Z "$upload_zip" | grep -qE '^l'; then
  die "sanitized theme zip still contains symlink entries"
fi
log "repacked theme as ${install_as}.zip without symlinks: $(stat -c %s "$upload_zip") bytes"

kid="$(admin_key_id)"; secret="$(admin_key_secret)"

log "uploading theme: POST $url/ghost/api/admin/themes/upload/"
token="$(make_jwt "$kid" "$secret")"
code="$(curl -sS -o "$body" -w '%{http_code}' -X POST "$url/ghost/api/admin/themes/upload/" \
  -H "Authorization: Ghost $token" \
  -H 'Accept-Version: v6.0' \
  -F "file=@$upload_zip")"
log "upload: HTTP $code"
jq '{themes: [.themes[].name]}' "$body" 2>/dev/null || cat "$body"
[ "$code" = "200" ] || [ "$code" = "201" ] || die "theme upload returned HTTP $code"

log "activating theme: PUT $url/ghost/api/admin/themes/$install_as/activate/"
token="$(make_jwt "$kid" "$secret")"
code="$(curl -sS -o "$body" -w '%{http_code}' -X PUT \
  "$url/ghost/api/admin/themes/$install_as/activate/" \
  -H "Authorization: Ghost $token" \
  -H 'Accept-Version: v6.0')"
log "activate: HTTP $code"
jq '{active: [.themes[] | select(.active==true) | .name]}' "$body" 2>/dev/null || cat "$body"
[ "$code" = "200" ] || die "theme activate returned HTTP $code"

log "apply: OK"
