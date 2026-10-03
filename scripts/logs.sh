#!/usr/bin/env bash
# Follow container logs. usage: logs.sh [--tail N] [service...]
set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

require_cmd docker
load_env

tail_n="${TAIL:-100}"
args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --tail) tail_n="$2"; shift 2 ;;
    --tail=*) tail_n="${1#--tail=}"; shift ;;
    *) args+=("$1"); shift ;;
  esac
done

compose logs --tail="$tail_n" -f "${args[@]}"
