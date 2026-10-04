#!/usr/bin/env bash
# Deploy the Ghost blog stack to an SSH-reachable machine that runs Docker, or
# run it against this checkout.
#
#   scripts/deploy.sh <user@host> [--dry-run]   stream the checkout, deploy over SSH
#   scripts/deploy.sh --local [--dry-run]       run against this checkout
#
# The script is non-interactive and idempotent. Every lifecycle step is
# delegated to this repo's own scripts, in order:
#   up.sh (docker compose up -d + health)
#   bootstrap.sh (owner + Admin API integration)
#   migrate.sh (boot-time migrations)
#   verify.sh (end-to-end gate)
# It presupposes only an SSH-reachable machine that has Docker: the checkout is
# streamed with tar over SSH, so the target needs only ssh, tar and docker.
# --dry-run prints the exact command sequence and touches nothing.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
REPO_NAME="$(basename "$ROOT_DIR")"
DEFAULT_PROJECT="template-blog-ghost"
URL_KEY="GHOST_URL"

usage() {
  cat >&2 <<'EOF'
usage: scripts/deploy.sh <user@host> [--dry-run]
       scripts/deploy.sh --local [--dry-run]

  <user@host>   SSH target that has Docker (checkout streamed over SSH)
  --local       run against this checkout instead of an SSH target
  --dry-run     print the exact command sequence and touch nothing

Environment:
  DEPLOY_DIR    target directory on the remote host (default: ~/<repo name>)
EOF
}

target=""
dry_run=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --local)   [ -z "$target" ] || { usage; exit 2; }; target="local" ;;
    -h|--help) usage; exit 0 ;;
    --*)       printf 'unknown option: %s\n' "$1" >&2; usage; exit 2 ;;
    *)         [ -z "$target" ] || { usage; exit 2; }; target="$1" ;;
  esac
  shift
done
[ -n "$target" ] || { usage; exit 2; }
if [ "$target" != "local" ]; then
  case "$target" in
    *@*) : ;;
    *) printf 'target must be <user@host> or --local\n' >&2; exit 2 ;;
  esac
fi

remote_dir="${DEPLOY_DIR:-$REPO_NAME}"
where="local"
[ "$target" = "local" ] || where="ssh $target"

# Read a KEY from the local .env, else from .env.example. Used only for the
# printed URL, never for a secret value.
local_env_value() {
  local key="$1" f v
  for f in "$ROOT_DIR/.env" "$ROOT_DIR/.env.example"; do
    [ -f "$f" ] || continue
    v="$(sed -n "s/^${key}=//p" "$f" | tail -n1)"
    [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  done
  return 1
}
url_preview() { local_env_value "$URL_KEY" || printf 'set %s in .env' "$URL_KEY"; }

# Run one shell step on the chosen target. In --dry-run mode it is printed.
run_step() {
  local cmd="$1"
  if [ "$dry_run" -eq 1 ]; then
    printf '[%s] %s\n' "$where" "$cmd"
  elif [ "$target" = "local" ]; then
    ( cd "$ROOT_DIR" && bash -c "$cmd" )
  else
    # shellcheck disable=SC2029
    ssh -o BatchMode=yes "$target" "cd '$remote_dir' && $cmd"
  fi
}

# 0. Sync the checkout to the target. Remote only; .env, secrets/, backups/,
#    runtime/ and .git are never sent. The target needs no rsync.
if [ "$target" != "local" ]; then
  sync_desc="tar -C '$ROOT_DIR' -czf - --exclude=.git --exclude=.env --exclude=backups --exclude=runtime --exclude=secrets . | ssh -o BatchMode=yes '$target' \"mkdir -p '$remote_dir' && tar -xzf - -C '$remote_dir'\""
  if [ "$dry_run" -eq 1 ]; then
    printf '[%s] %s\n' "$target" "$sync_desc"
  else
    ssh -o BatchMode=yes "$target" "mkdir -p '$remote_dir'"
    tar -C "$ROOT_DIR" -czf - \
      --exclude=.git --exclude=.env --exclude=backups --exclude=runtime --exclude=secrets . \
      | ssh -o BatchMode=yes "$target" "tar -xzf - -C '$remote_dir'"
  fi
fi

# 1. Ensure .env exists on the target (the shipped example is the template).
run_step 'if [ ! -f .env ]; then cp .env.example .env; fi; echo "env: .env present"'

# 2. Ghost DB password file secret: create a throwaway when absent. A
#    production operator ships the real file from the secret store instead.
run_step 'mkdir -p secrets; if [ ! -s secrets/mysql_root_password.txt ]; then openssl rand -base64 24 > secrets/mysql_root_password.txt; fi; chmod 700 secrets; chmod 444 secrets/mysql_root_password.txt; echo "secret: secrets/mysql_root_password.txt ready"'

# 3. Render the compose config from .env (read-only) and refuse the protected
#    production project. --project-name is explicit because a bare `docker
#    compose` on a host that exports COMPOSE_PROJECT_NAME would target it.
run_step 'proj="$(sed -n "s/^COMPOSE_PROJECT_NAME=//p" .env | tail -n1)"; [ -n "$proj" ] || proj="template-blog-ghost"; [ "$proj" != "omni-stack" ] || { echo "refusing to target the protected project omni-stack" >&2; exit 1; }; docker compose --project-name "$proj" --env-file .env -f docker-compose.yml config >/dev/null; echo "config: rendered for project $proj"'

# 4. Lifecycle: up -> bootstrap -> migrate -> verify, all via existing scripts.
run_step 'scripts/up.sh'
run_step 'scripts/bootstrap.sh'
run_step 'scripts/migrate.sh'
run_step 'scripts/verify.sh'

if [ "$dry_run" -eq 1 ]; then
  printf '[%s] URL after deploy: %s\n' "$where" "$(url_preview)"
  exit 0
fi

# Print the URL the stack serves.
if [ "$target" = "local" ]; then
  url="$(local_env_value "$URL_KEY" 2>/dev/null || true)"
else
  url="$(ssh -o BatchMode=yes "$target" "cd '$remote_dir' && sed -n 's/^${URL_KEY}=//p' .env | tail -n1")"
fi
printf 'deploy: OK, URL %s\n' "${url:-<set $URL_KEY in .env>}"
