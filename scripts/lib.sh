#!/usr/bin/env bash
# Shared helpers for the lifecycle scripts. This file is SOURCED, never run.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
COMPOSE_FILE="${COMPOSE_FILE:-$ROOT_DIR/docker-compose.yml}"
RUNTIME_DIR="${RUNTIME_DIR:-$ROOT_DIR/runtime}"

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

load_env() {
  [ -f "$ENV_FILE" ] || die "missing $ENV_FILE (run: cp .env.example .env, then edit it)"
  # Parse .env line by line instead of `source`-ing it: values may contain
  # spaces (a blog title) and `source` would try to execute them. One layer of
  # surrounding quotes is stripped, so both `K=v w` and `K="v w"` work.
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    case "$line" in *=*) : ;; *) continue ;; esac
    key="${line%%=*}"
    val="${line#*=}"
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    case "$val" in
      \"*\") val="${val#\"}"; val="${val%\"}" ;;
      \'*\') val="${val#\'}"; val="${val%\'}" ;;
    esac
    export "$key=$val"
  done < "$ENV_FILE"
  # The operator's shell may already define COMPOSE_PROJECT_NAME (a host that
  # runs its own compose project exports one). The .env value must win, so it is
  # re-exported from the file below and pinned with `-p` in compose().
  COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-template-blog-ghost}"
  export COMPOSE_PROJECT_NAME
}

# Every compose call is pinned to this stack's project name. Never run a bare
# `docker compose` in this directory: on a host that exports COMPOSE_PROJECT_NAME
# for a DIFFERENT project, a bare call would target that project instead. The
# guard below refuses the production project name outright.
compose() {
  [ "${COMPOSE_PROJECT_NAME:-}" != "omni-stack" ] \
    || die "refusing to run compose against the protected omni-stack project"
  docker compose --project-name "$COMPOSE_PROJECT_NAME" \
    --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

stack_url() {
  local u="${GHOST_URL:?GHOST_URL is not set in $ENV_FILE}"
  printf '%s' "${u%/}"
}

require_creds() {
  [ -f "$RUNTIME_DIR/admin-api.json" ] \
    || die "missing $RUNTIME_DIR/admin-api.json; run scripts/bootstrap.sh first"
}

admin_key_id() { jq -r '.api_keys[] | select(.type=="admin") | .id' "$RUNTIME_DIR/admin-api.json"; }
admin_key_secret() { jq -r '.api_keys[] | select(.type=="admin") | .secret' "$RUNTIME_DIR/admin-api.json"; }

# Sign a Ghost Admin API JWT (official scheme):
#   header  {"alg":"HS256","typ":"JWT","kid":"<id>"}
#   payload {"iat":<now>,"exp":<now+300>,"aud":"/admin/"}
#   HS256 over the HEX-DECODED integration secret.
make_jwt() {
  local kid="$1" secret="$2"
  if command -v node >/dev/null 2>&1; then
    KID="$kid" SECRET="$secret" node -e '
      const c = require("crypto");
      const b64 = (o) => Buffer.from(typeof o === "string" ? o : JSON.stringify(o)).toString("base64url");
      const iat = Math.floor(Date.now() / 1000);
      const h = b64({ alg: "HS256", typ: "JWT", kid: process.env.KID });
      const p = b64({ iat, exp: iat + 300, aud: "/admin/" });
      const s = c.createHmac("sha256", Buffer.from(process.env.SECRET, "hex"))
                 .update(h + "." + p).digest("base64url");
      process.stdout.write(h + "." + p + "." + s);
    '
  elif command -v openssl >/dev/null 2>&1; then
    local b64u iat header payload sig
    b64u() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
    iat="$(date -u +%s)"
    header="$(printf '{"alg":"HS256","typ":"JWT","kid":"%s"}' "$kid" | b64u)"
    payload="$(printf '{"iat":%s,"exp":%s,"aud":"/admin/"}' "$iat" "$((iat + 300))" | b64u)"
    sig="$(printf '%s' "$header.$payload" \
      | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$secret" -binary | b64u)"
    printf '%s' "$header.$payload.$sig"
  else
    die "need node or openssl to sign the Admin API JWT"
  fi
}

wait_for_healthy() {
  local service="$1" tries="${2:-60}" i=1 status
  while [ "$i" -le "$tries" ]; do
    status="$(compose ps --format '{{.Health}}' "$service" 2>/dev/null | head -n1 || true)"
    [ "$status" = "healthy" ] && return 0
    sleep 5
    i=$((i + 1))
  done
  return 1
}
